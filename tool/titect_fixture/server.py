"""Consumer-owned persistent HTTP fixture importing the pinned composition."""

import argparse
import asyncio
import json
import os
import sys
from contextlib import AsyncExitStack, asynccontextmanager
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any


def build(reference, schema, barrier_point, *, exact=False, delay=0):
    sys.path[:0] = [str(reference), str(reference / "src")]
    from examples.fastapi_event_platform.composition import build_app
    from fastapi import Request
    from fastapi.responses import JSONResponse, Response
    from pytitect.core import OpaqueId
    from pytitect.idempotency import IdempotencyPolicy, IdempotencyScope
    from pytitect.operations import ReadinessPolicy, RuntimeRole
    from pytitect.sqlalchemy import SQLAlchemyIdempotentRequest
    from pytitect.sqlalchemy.models import IdempotencyModelMixin, ReceiptModelMixin
    from pytitect.sync import (
        EXACT_JSON_INTEGRITY,
        ExactJsonSha256Integrity,
        decode_sync_document,
        encode_sync_document,
    )
    from pytitect.wire import WireDocument
    from sqlalchemy import JSON, Integer, String, UniqueConstraint, event, select
    from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
    from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
    from sqlalchemy.schema import CreateSchema

    class Base(DeclarativeBase):
        type_annotation_map = {dict[str, Any]: JSON}

    class Idempotency(IdempotencyModelMixin, Base):
        __tablename__ = "idempotency"
        id: Mapped[int] = mapped_column(primary_key=True)
        __table_args__ = (
            UniqueConstraint("namespace", "subject", "operation", "key"),
            UniqueConstraint("token"),
        )

    class Receipt(ReceiptModelMixin, Base):
        __tablename__ = "receipt"
        receipt_id: Mapped[str] = mapped_column(String(255), primary_key=True)

    class Item(Base):
        __tablename__ = "item"
        identity: Mapped[str] = mapped_column(String(255), primary_key=True)
        value: Mapped[int] = mapped_column(Integer)

    class Effect(Base):
        __tablename__ = "effect"
        identity: Mapped[str] = mapped_column(String(255), primary_key=True)
        payload: Mapped[dict] = mapped_column(JSON)

    class JsonSerializer:
        def encode(self, value):
            return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()

        def decode(self, value):
            return json.loads(value)

    dsn = os.environ["TITECT_POSTGRES_DSN"].replace(
        "postgresql://", "postgresql+psycopg://"
    )
    engine = create_async_engine(
        dsn,
        pool_size=2,
        max_overflow=0,
        pool_timeout=5,
        connect_args={"application_name": schema, "connect_timeout": 5},
        execution_options={"schema_translate_map": {None: schema}},
    )
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    counters = {
        "connections": 0,
        "peakConnections": 0,
        "active": 0,
        "peakActive": 0,
        "accepted": 0,
        "refused": 0,
    }

    @event.listens_for(engine.sync_engine, "checkout")
    def checkout(*_):
        counters["connections"] += 1
        counters["peakConnections"] = max(
            counters["peakConnections"], counters["connections"]
        )

    @event.listens_for(engine.sync_engine, "checkin")
    def checkin(*_):
        counters["connections"] -= 1

    async def barrier(point):
        if point == barrier_point:
            print("BARRIER:" + point, flush=True)
            await asyncio.Event().wait()

    async def mutate(session, payload):
        if (
            set(payload) != {"id", "value"}
            or not isinstance(payload["id"], str)
            or type(payload["value"]) is not int
        ):
            raise ValueError("invalid synthetic consumer mutation")
        session.add(Item(identity=payload["id"], value=payload["value"]))
        session.add(Effect(identity=payload["id"], payload=payload))
        await session.flush()
        await barrier("remote_before_commit")
        return payload

    requests = SQLAlchemyIdempotentRequest(
        sessions,
        idempotency_model=Idempotency,
        receipt_model=Receipt,
        serializer=JsonSerializer(),
        policy=IdempotencyPolicy(
            timedelta(seconds=30), timedelta(days=1), timedelta(days=1)
        ),
    )
    scope = IdempotencyScope("titect-fixture", "synthetic", "mutation")
    app = build_app(
        requests=requests,
        mutate=mutate,
        request_scope=lambda _: scope,
        receipt_identity=lambda _, key: OpaqueId("receipt:" + key),
        readiness_policy=ReadinessPolicy(RuntimeRole.API, ()),
    )
    exact_lifespan = ExactBytes = exact_codec = None
    if exact:
        from exact_transport import install

        exact_lifespan, ExactBytes, exact_codec = install(
            app, Base, sessions, engine, Idempotency, Receipt, schema, delay
        )

    @asynccontextmanager
    async def lifespan(_):
        async with engine.begin() as connection:
            await connection.execute(CreateSchema(schema, if_not_exists=True))
            await connection.run_sync(Base.metadata.create_all)
        try:
            async with AsyncExitStack() as stack:
                if exact_lifespan:
                    await stack.enter_async_context(exact_lifespan())
                print("READY", flush=True)
                yield
        finally:
            await engine.dispose()
            print("RESIDUAL:" + json.dumps(counters, sort_keys=True), flush=True)

    app.router.lifespan_context = lifespan

    @app.middleware("http")
    async def admission(request: Request, call_next):
        if request.url.path in ("/metrics", "/exact-metrics"):
            return await call_next(request)
        if counters["active"] >= 2:
            counters["refused"] += 1
            return JSONResponse(
                {"reason": "busy"}, status_code=503, headers={"Retry-After": "1"}
            )
        counters["active"] += 1
        counters["accepted"] += 1
        counters["peakActive"] = max(counters["peakActive"], counters["active"])
        try:
            response = await call_next(request)
            if request.url.path == "/operations":
                await barrier("remote_after_commit")
            return response
        finally:
            counters["active"] -= 1

    def wire(kind, payload):
        return encode_sync_document(
            decode_sync_document(
                {"protocol": "titect-sync/1", "kind": kind, "payload": payload}
            )
        )

    @app.get("/bootstrap")
    @app.post("/bootstrap")
    async def bootstrap(request: Request):
        now = datetime.now(UTC)
        selected = False
        if request.method == "POST":
            raw = bytearray()
            async for chunk in request.stream():
                if len(raw) + len(chunk) > 8192:
                    raise ValueError("bootstrap byte bound exceeded")
                raw.extend(chunk)
            from pytitect.sync import decode_sync_raw

            document = decode_sync_raw(bytes(raw)).document.value
            selected = EXACT_JSON_INTEGRITY in document["payload"]["capabilities"]

        def stamp(value):
            return value.isoformat(timespec="milliseconds").replace("+00:00", "Z")

        return JSONResponse(
            wire(
                "bootstrap_response",
                {
                    "session": {
                        "session_id": schema,
                        "created_at": stamp(now),
                        "expires_at": stamp(now + timedelta(minutes=5)),
                    },
                    "datasets": [
                        {
                            "dataset_id": "items",
                            "generation": 1,
                            "modes": ["snapshot", "delta"],
                        }
                    ],
                    "limits": {
                        "max_document_bytes": 1048576,
                        "max_datasets": 128,
                        "max_items_per_page": 1000,
                        "max_mutations": 1000,
                        "max_opaque_id_bytes": 255,
                        "max_capabilities": 32,
                    },
                },
            ),
            headers={"Titect-Sync-Integrity": EXACT_JSON_INTEGRITY} if selected else {},
        )

    @app.get("/pages")
    async def pages(request: Request, cursor: str | None = None, fault: str = ""):
        # These cursor semantics are fixture-owned and never interpreted by Dart.
        if cursor == "expired":
            return JSONResponse(
                wire(
                    "reset_required",
                    {"dataset_id": "items", "generation": 1, "reason": "expired"},
                )
            )
        offset = 0 if cursor is None else int(cursor.removeprefix("opaque/+="))
        async with sessions() as session:
            rows = (
                await session.scalars(
                    select(Item).order_by(Item.identity).offset(offset).limit(3)
                )
            ).all()
        items = [
            {"item_id": row.identity, "revision": 1, "value": {"value": row.value}}
            for row in rows[:2]
        ]
        payload = {
            "dataset_id": "items",
            "generation": 1,
            "upserts": items,
            "next_cursor": "opaque/+=" + str(offset + 2) if len(rows) > 2 else None,
            "integrity": {
                "algorithm": "sha-256",
                "digest": "a" * 64,
                "item_count": len(items),
            },
        }
        if ExactBytes is not None:
            async with sessions() as session:
                exact_rows = (
                    await session.scalars(
                        select(ExactBytes).order_by(ExactBytes.identity).limit(3)
                    )
                ).all()
            if exact_rows:
                payload["upserts"] = [
                    {
                        "item_id": row.identity,
                        "revision": 1,
                        "value": exact_codec.decode(bytes(row.sent)).data.value,
                    }
                    for row in exact_rows[:2]
                ]
                payload["next_cursor"] = None
                payload["integrity"]["item_count"] = len(payload["upserts"])
        selected = request.headers.get("Titect-Sync-Integrity") == EXACT_JSON_INTEGRITY
        if not selected:
            return JSONResponse(wire("snapshot", payload))
        # Lift consumer integer metadata explicitly; arbitrary exact data is
        # already a WireDocument from the selected /2 decoder.
        from collections.abc import Mapping

        from pytitect.wire import ExactNumber

        def exact_value(value):
            if type(value) is int:
                return ExactNumber(str(value))
            if isinstance(value, (list, tuple)):
                return tuple(exact_value(item) for item in value)
            if isinstance(value, Mapping):
                return {key: exact_value(item) for key, item in value.items()}
            return value

        page = (
            ExactJsonSha256Integrity()
            .seal(
                WireDocument(
                    exact_value(
                        {
                            "protocol": "titect-sync/1",
                            "kind": "snapshot",
                            "payload": payload,
                        }
                    )
                )
            )
            .encode()
        )
        if fault == "corrupt":
            page = page.replace(b'"generation":1', b'"generation":2')
        header = (
            {}
            if fault == "missing"
            else {
                "Titect-Sync-Integrity": "changed"
                if fault == "mismatch"
                else EXACT_JSON_INTEGRITY
            }
        )
        return Response(page, media_type="application/json", headers=header)

    @app.get("/metrics")
    async def metrics():
        return dict(counters)

    return app


if __name__ == "__main__":
    import uvicorn

    parser = argparse.ArgumentParser()
    parser.add_argument("--python-root", type=Path, required=True)
    parser.add_argument("--schema", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--barrier", default="")
    parser.add_argument("--exact", action="store_true")
    parser.add_argument("--delay", type=float, default=0)
    args = parser.parse_args()
    if (
        not args.schema.startswith("titect_")
        or not args.schema.replace("_", "").isalnum()
    ):
        raise SystemExit("invalid isolated fixture schema")
    uvicorn.run(
        build(
            args.python_root.resolve(strict=True),
            args.schema,
            args.barrier,
            exact=args.exact,
            delay=args.delay,
        ),
        host="127.0.0.1",
        port=args.port,
        log_level="warning",
    )
