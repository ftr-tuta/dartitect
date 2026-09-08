"""Consumer-owned exact HTTP/PostgreSQL/JetStream composition for paired probes."""

import asyncio
import hashlib
import json
import os
import resource
from contextlib import asynccontextmanager
from datetime import UTC, datetime, timedelta


def install(app, Base, sessions, engine, Idempotency, Receipt, schema, delay):
    import nats
    from fastapi import Request
    from fastapi.responses import JSONResponse, Response
    from nats.js.api import ConsumerConfig
    from pytitect.aio import AsyncConsumer, AsyncRelay, InMemoryRejectedDeliveryStore
    from pytitect.application import Decision
    from pytitect.core import OpaqueId
    from pytitect.idempotency import (
        IdempotencyPolicy,
        IdempotencyScope,
        Replay,
        RequestFingerprint,
    )
    from pytitect.messaging import ExactJsonMessageCodec, Route, RoutingTable
    from pytitect.nats import NatsDelivery, NatsJetStreamPublisher
    from pytitect.outbox import OutboxEnvelope
    from pytitect.sqlalchemy import (
        SQLAlchemyIdempotentRequest,
        SQLAlchemyUnitOfWorkFactory,
    )
    from pytitect.sqlalchemy.idempotency import RequestCommitted
    from pytitect.sqlalchemy.models import InboxModelMixin, OutboxModelMixin
    from pytitect.sqlalchemy.relay import SQLAlchemyRelayStore
    from pytitect.sqlalchemy.stores import SQLAlchemyOutboxStore
    from sqlalchemy import LargeBinary, String, UniqueConstraint, func, select, text
    from sqlalchemy.orm import Mapped, mapped_column

    class Outbox(OutboxModelMixin, Base):
        __tablename__ = "exact_outbox"
        message_id: Mapped[str] = mapped_column(String(255), primary_key=True)

    class Inbox(InboxModelMixin, Base):
        __tablename__ = "exact_inbox"
        id: Mapped[int] = mapped_column(primary_key=True)
        __table_args__ = (
            UniqueConstraint("namespace", "source", "consumer", "message_id"),
        )

    class Bytes(Base):
        __tablename__ = "exact_bytes"
        identity: Mapped[str] = mapped_column(String(255), primary_key=True)
        sent: Mapped[bytes] = mapped_column(LargeBinary)
        received: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)

    codec = ExactJsonMessageCodec(max_envelope_bytes=8192)
    scope = IdempotencyScope("exact", "synthetic", "mutation")
    requests = SQLAlchemyIdempotentRequest(
        sessions,
        idempotency_model=Idempotency,
        receipt_model=Receipt,
        serializer=codec,
        policy=IdempotencyPolicy(
            timedelta(seconds=2), timedelta(days=1), timedelta(days=1)
        ),
    )
    tasks = []
    peers = []
    counts = {"publication_retries": 0, "published": 0, "consumed": 0}

    async def raw_message(request):
        body = bytearray()
        async for chunk in request.stream():
            if len(chunk) > 8192 - len(body):
                raise ValueError("bounded exact fixture input exceeded")
            body.extend(chunk)
        wire = bytes(body)
        message = codec.decode(wire)
        if (
            codec.encode(message) != wire
            or request.headers.get("idempotency-key") != message.id
        ):
            raise ValueError("Dart exact bytes or identity differ")
        return message, wire

    def fingerprint(wire):
        return RequestFingerprint.from_json(hashlib.sha256(wire).hexdigest())

    @app.post("/exact-operations")
    async def operation(request: Request):
        message, wire = await raw_message(request)

        async def mutate(session):
            if delay:
                await session.execute(text("SELECT pg_sleep(:delay)"), {"delay": delay})
            session.add(Bytes(identity=message.id, sent=wire))
            admitted_at = datetime.now(UTC)
            await SQLAlchemyOutboxStore(session, Outbox, codec).add(
                OutboxEnvelope(
                    OpaqueId(message.id), schema, message, admitted_at, admitted_at
                )
            )
            return message

        result = await requests.execute(
            scope=scope,
            key=message.id,
            fingerprint=fingerprint(wire),
            receipt_id=OpaqueId("exact:" + message.id),
            mutate=mutate,
        )
        if isinstance(result, (RequestCommitted, Replay)):
            return Response(
                codec.encode(result.value),
                media_type="application/json",
                status_code=201 if isinstance(result, RequestCommitted) else 200,
            )
        return JSONResponse({"status": "uncertain"}, status_code=202)

    @app.post("/exact-reconciliation")
    async def reconcile(request: Request):
        message, wire = await raw_message(request)
        result = await requests.reconcile(
            scope=scope, key=message.id, fingerprint=fingerprint(wire)
        )
        if isinstance(result, Replay):
            return Response(codec.encode(result.value), media_type="application/json")
        # No resend is authorized by a 202. An absent durable reservation and
        # effect establish that a killed transaction did not commit.
        async with sessions() as session:
            reserved = await session.scalar(
                select(func.count())
                .select_from(Idempotency)
                .where(Idempotency.namespace == "exact", Idempotency.key == message.id)
            )
            effect = await session.get(Bytes, message.id)
        return JSONResponse(
            {"status": "absent" if not reserved and effect is None else "uncertain"},
            status_code=404 if not reserved and effect is None else 202,
        )

    @app.get("/exact-bytes/{identity}")
    async def stored(identity: str):
        async with sessions() as session:
            row = await session.get(Bytes, identity)
            if row is None or row.received is None:
                return JSONResponse({"status": "pending"}, status_code=202)
            if bytes(row.sent) != bytes(row.received):
                raise ValueError("JetStream bytes differ from Dart HTTP bytes")
            return Response(bytes(row.received), media_type="application/json")

    async def metrics():
        async with sessions() as session:
            pending, oldest = (
                await session.execute(
                    select(func.count(), func.min(Outbox.occurred_at)).where(
                        Outbox.delivered_at.is_(None)
                    )
                )
            ).one()
            waits = await session.scalar(
                text(
                    "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type='Lock' AND application_name=:name"
                ),
                {"name": schema},
            )
            receipts = await session.scalar(
                select(func.count())
                .select_from(Receipt)
                .where(Receipt.receipt_id.startswith("exact:"))
            )
            outbox = await session.scalar(select(func.count()).select_from(Outbox))
            inbox = await session.scalar(
                select(func.count())
                .select_from(Inbox)
                .where(Inbox.completed_at.is_not(None))
            )
            retries = await session.scalar(
                select(func.coalesce(func.sum(Outbox.attempt), 0))
            )
            mismatched = await session.scalar(
                select(func.count())
                .select_from(Bytes)
                .where(Bytes.received.is_not(None), Bytes.sent != Bytes.received)
            )
        return {
            **counts,
            "rss_kib": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
            "tasks": len(asyncio.all_tasks()),
            "connections": engine.pool.checkedout(),
            "database_lock_waiters": waits,
            "backlog_age_seconds": 0
            if oldest is None
            else max(0, (datetime.now(UTC) - oldest).total_seconds()),
            "background_ok": bool(tasks) and not any(task.done() for task in tasks),
            "durable": {
                "receipts": receipts,
                "outbox": outbox,
                "inbox": inbox,
                "publication_retries": int(retries),
                "pending_outbox": pending,
                "byte_mismatches": mismatched,
            },
        }

    @app.get("/exact-metrics")
    async def observed():
        return await metrics()

    @asynccontextmanager
    async def lifespan():
        client = await nats.connect(
            os.environ["TITECT_NATS_URL"], connect_timeout=3, max_reconnect_attempts=5
        )
        peers.append(client)
        js = client.jetstream()
        # The runner owns this named stream across server crashes and removes it.
        await js.add_stream(
            name=schema, subjects=[schema], max_msgs=1600, max_bytes=16 * 1024 * 1024
        )
        subscription = await js.pull_subscribe(
            schema,
            durable="exact",
            config=ConsumerConfig(ack_wait=1, max_deliver=50, max_ack_pending=8),
        )
        relay = AsyncRelay(
            SQLAlchemyRelayStore(sessions, Outbox, codec),
            NatsJetStreamPublisher(js, codec=codec),
            RoutingTable([Route("example.changed.v1", schema)]),
            concurrency=2,
            max_admitted=4,
            max_retained_bytes=32768,
            claim_ttl=timedelta(seconds=1),
            publish_timeout=timedelta(seconds=2),
            round_timeout=timedelta(seconds=4),
        )

        async def save(session, decision):
            row = await session.get(Bytes, decision.result["id"])
            encoded = bytes.fromhex(decision.result["wire"])
            if row is None or bytes(row.sent) != encoded:
                raise ValueError(
                    "received exact message differs from committed Dart bytes"
                )
            row.received = encoded

        consumer = AsyncConsumer(
            consumer="exact",
            namespace="paired",
            handler=lambda message, _: Decision(
                result={"id": message.id, "wire": codec.encode(message).hex()}
            ),
            unit_of_work=SQLAlchemyUnitOfWorkFactory(
                sessions, inbox_model=Inbox, save_decision=save
            ),
            quarantine=InMemoryRejectedDeliveryStore(),
            codec=codec,
            concurrency=2,
            queue_capacity=4,
            max_message_bytes=8192,
            max_retained_bytes=49152,
            handler_timeout=timedelta(seconds=3),
        )

        async def publish():
            while True:
                result = await relay.run_once(limit=4)
                counts["publication_retries"] += result.retried
                counts["published"] += result.delivered
                await asyncio.sleep(0.01)

        async def consume():
            while True:
                try:
                    received = await subscription.fetch(4, timeout=0.2)
                except TimeoutError:
                    continue

                async def source():
                    for raw in received:
                        decoded = codec.decode(raw.data)
                        if (
                            codec.encode(decoded) != raw.data
                            or raw.headers["Titect-Profile"] != "titect-message/2"
                        ):
                            raise ValueError("broker wire or selected profile differs")
                        yield NatsDelivery(raw, codec=codec)

                counts["consumed"] += (await consumer.run(source())).acknowledged

        try:
            tasks.extend(
                [asyncio.create_task(publish()), asyncio.create_task(consume())]
            )
            yield
        finally:
            for task in tasks:
                task.cancel()
            results = await asyncio.gather(*tasks, return_exceptions=True)
            await subscription.unsubscribe()
            await client.close()
            print(
                "EXACT_RESIDUAL:"
                + json.dumps(
                    {
                        "tasks": sum(not task.done() for task in tasks),
                        "natsConnections": sum(not peer.is_closed for peer in peers),
                    }
                ),
                flush=True,
            )
            for value in results:
                if isinstance(value, BaseException) and not isinstance(
                    value, asyncio.CancelledError
                ):
                    raise RuntimeError("exact transport background failed") from value

    return lifespan, Bytes, codec
