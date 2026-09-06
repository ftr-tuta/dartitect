"""Deterministic process-death probes against consumer Drift and Python stores."""

import argparse
import importlib.metadata
import json
import os
import queue
import signal
import sqlite3
import subprocess
import sys
import threading
import time
import uuid
from pathlib import Path
from urllib.error import URLError
from urllib.request import urlopen

from run_titect_conformance import (
    FIXTURE,
    ROOT,
    cancel_on_termination,
    digest,
    evidence_identity,
    execution_reference,
    fresh_output,
    git,
    run_captured,
    write_report,
)


class Child:
    def __init__(self, args, log, env=None, executable_sha256=None):
        if (
            executable_sha256
            and digest(Path(args[0]).read_bytes()) != executable_sha256
        ):
            raise ValueError("native actor changed before execution")
        self.process = subprocess.Popen(
            args,
            cwd=ROOT,
            env=env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            start_new_session=True,
        )
        if executable_sha256 and sys.platform == "linux":
            try:
                if (
                    digest(Path(f"/proc/{self.process.pid}/exe").read_bytes())
                    != executable_sha256
                ):
                    raise ValueError("executed native actor differs from recorded hash")
            except BaseException:
                self.process.kill()
                self.process.wait(timeout=10)
                raise
        self.events = queue.Queue()
        self.lines = []
        self.log = log
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()

    def _read(self):
        for line in self.process.stdout:
            self.lines.append(line)
            self.events.put(line.strip())
        self.events.put(None)

    def wait_for(self, event):
        deadline = time.monotonic() + 30
        while True:
            line = self.events.get(timeout=max(0.01, deadline - time.monotonic()))
            if line is None:
                raise RuntimeError(
                    f"child exited before {event}: {''.join(self.lines)[-2000:]}"
                )
            if line == event:
                return
            if time.monotonic() >= deadline:
                raise TimeoutError(event)

    def resume(self):
        self.process.stdin.write("continue\n")
        self.process.stdin.flush()

    def finish(self, *, kill=False, terminate=False, success=True):
        if kill and self.process.poll() is None:
            os.killpg(self.process.pid, signal.SIGKILL)
        elif terminate and self.process.poll() is None:
            os.killpg(self.process.pid, signal.SIGTERM)
        try:
            code = self.process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            os.killpg(self.process.pid, signal.SIGKILL)
            self.process.wait(timeout=10)
            raise
        finally:
            self.reader.join(timeout=5)
            self.log.write_text("".join(self.lines))
            self.process.stdin.close()
            self.process.stdout.close()
        if terminate and success:
            residual = [
                json.loads(line.removeprefix("RESIDUAL:"))
                for line in self.lines
                if line.startswith("RESIDUAL:")
            ]
            if (
                code not in (0, -signal.SIGTERM)
                or len(residual) != 1
                or residual[0]["active"]
                or residual[0]["connections"]
            ):
                raise RuntimeError("server termination did not prove cleanup")
        elif success and not kill and code != 0:
            raise RuntimeError(f"child failed ({code}): {''.join(self.lines)[-2000:]}")
        return code


def local(path, sql, parameters=()):
    # Every assertion uses a new independent SQLite connection after termination.
    with sqlite3.connect(path) as connection:
        return connection.execute(sql, parameters).fetchall()


def main():
    cancel_on_termination()
    import psycopg
    from psycopg import sql

    parser = argparse.ArgumentParser()
    parser.add_argument("--python-root", type=Path, required=True)
    parser.add_argument("--actor", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--port", type=int, default=55439)
    parser.add_argument("--preliminary", action="store_true")
    parser.add_argument("--reference-manifest", type=Path)
    parser.add_argument("--django-python", default=sys.executable)
    args = parser.parse_args()
    args.python_root = args.python_root.resolve()
    args.actor = args.actor.resolve()
    fresh_output(args.output)
    dsn = os.environ.get("TITECT_POSTGRES_DSN")
    pin = json.loads((FIXTURE / "pin.json").read_text())
    report = {
        "schemaVersion": 1,
        "status": "failed",
        "preliminary": args.preliminary,
        **evidence_identity(pin),
        "scenarios": [],
        "residualResources": None,
        "parameters": {
            "concurrency": 2,
            "queue": 4,
            "maxAttempts": 30,
            "maxPages": 10,
            "maxReceivedBytes": 1048576,
            "maxRetainedRows": 100,
            "maxScopeSeconds": 30,
        },
    }
    children, schemas = [], []
    streams = []
    serial = 0

    def start_server(schema, point="", *, exact=False):
        nonlocal serial
        serial += 1
        child = Child(
            [
                sys.executable,
                str(FIXTURE / "server.py"),
                "--python-root",
                str(args.python_root),
                "--schema",
                schema,
                "--port",
                str(args.port),
                "--barrier",
                point,
                *(["--exact"] if exact else []),
            ],
            args.output / f"server-{serial}.log",
        )
        children.append(child)
        child.wait_for("READY")
        deadline = time.monotonic() + 10
        while True:
            try:
                with urlopen(
                    f"http://127.0.0.1:{args.port}/metrics", timeout=0.5
                ) as response:
                    if response.status == 200:
                        break
            except (URLError, TimeoutError, ConnectionError):
                pass
            if time.monotonic() >= deadline:
                raise TimeoutError("recovery HTTP readiness deadline exceeded")
            time.sleep(0.02)
        return child

    def actor(
        mode,
        path,
        *,
        point="none",
        owner="session",
        token=1,
        identity="item",
        extra=(),
        wait=True,
        success=True,
    ):
        nonlocal serial
        serial += 1
        child = Child(
            [
                str(args.actor),
                mode,
                str(path),
                f"http://127.0.0.1:{args.port}",
                owner,
                str(token),
                point,
                identity,
                *extra,
            ],
            args.output / f"actor-{serial}.log",
            executable_sha256=report["nativeActorSha256"],
        )
        children.append(child)
        if wait:
            child.finish(success=success)
            if success:
                residual = [
                    json.loads(line.removeprefix("RESIDUAL:"))
                    for line in child.lines
                    if line.startswith("RESIDUAL:")
                ]
                if (
                    len(residual) != 1
                    or residual[0]["running"]
                    or residual[0]["queued"]
                    or not residual[0]["databaseClosed"]
                    or not residual[0]["httpClientClosed"]
                ):
                    raise RuntimeError("actor did not prove owned resource cleanup")
        return child

    def remote_count(schema, table):
        with psycopg.connect(dsn) as connection:
            return connection.execute(
                sql.SQL("SELECT count(*) FROM {}.{}").format(
                    sql.Identifier(schema), sql.Identifier(table)
                )
            ).fetchone()[0]

    try:
        if not dsn or not os.environ.get("TITECT_NATS_URL"):
            raise ValueError("real PostgreSQL and JetStream settings are required")
        if sys.flags.optimize:
            raise ValueError("recovery assertions require Python optimization disabled")
        report["reference"] = execution_reference(
            args.python_root.resolve(strict=True),
            pin,
            args.preliminary,
            args.reference_manifest,
        )
        report["preliminary"] = report["reference"]["mode"] == "candidate"
        report["releaseEligible"] = not report["preliminary"]
        report["pythonSha"] = report["reference"]["pythonSha"]
        write_report(args.output, "reference", report["reference"])
        report["referenceSha256"] = digest(
            (args.output / "reference.json").read_bytes()
        )
        report["pythonMainSha"] = git(
            args.python_root, "rev-parse", "refs/remotes/origin/main"
        )
        report["dartVersion"] = subprocess.check_output(
            ["dart", "--version"], text=True
        ).strip()
        report["chromeVersion"] = subprocess.check_output(
            [os.environ["CHROME_EXECUTABLE"], "--version"], text=True
        ).strip()
        report["nativeActorSha256"] = digest(args.actor.read_bytes())
        report["providerVersions"] = {
            name: importlib.metadata.version(name)
            for name in ["fastapi", "SQLAlchemy", "psycopg", "uvicorn"]
        }
        report["providerVersions"]["sqlite3"] = sqlite3.sqlite_version
        with psycopg.connect(dsn) as version_connection:
            report["providerVersions"]["postgres"] = version_connection.execute(
                "SELECT version()"
            ).fetchone()[0]
        started = time.monotonic()
        if list(args.output.glob("*.sqlite")):
            raise ValueError("recovery execution requires a fresh database directory")
        if not args.actor.is_file():
            raise ValueError("compiled native actor is required")
        for point in [
            "local_before_commit",
            "local_after_commit",
            "remote_before_commit",
            "remote_after_commit",
            "response_received",
        ]:
            schema = "titect_" + uuid.uuid4().hex
            schemas.append(schema)
            server = start_server(schema, point if point.startswith("remote_") else "")
            path = args.output / f"{point}.sqlite"
            actor("acquire", path)
            child = actor("mutate", path, point=point, wait=False)
            (server if point.startswith("remote_") else child).wait_for(
                "BARRIER:" + point
            )
            if point.startswith("remote_"):
                server.finish(kill=True)
                child.finish()
                server = start_server(schema)
            else:
                child.finish(kill=True)
            committed_local = point != "local_before_commit"
            assert local(path, "SELECT count(*) FROM fixture_tasks")[0][0] == int(
                committed_local
            )
            assert local(path, "SELECT count(*) FROM fixture_outbox")[0][0] == int(
                committed_local
            )
            committed_remote = point in {"remote_after_commit", "response_received"}
            assert remote_count(schema, "item") == int(committed_remote)
            assert remote_count(schema, "effect") == int(committed_remote)
            assert remote_count(schema, "receipt") == int(committed_remote)
            actor("recover", path)
            if point == "local_after_commit":
                committed_remote = True
            actor("reconcile", path)
            assert remote_count(schema, "item") == int(committed_remote)
            if committed_local:
                status, key = local(
                    path, "SELECT status,idempotency_key FROM fixture_outbox"
                )[0]
                assert key == "mutation:item"
                assert status == ("synced" if committed_remote else "uncertain")
            actor("expire", path)
            server.finish(terminate=True)
            report["scenarios"].append(
                {
                    "name": point,
                    "passed": True,
                    "localCommitted": committed_local,
                    "remoteCommitted": committed_remote,
                }
            )

        schema = "titect_" + uuid.uuid4().hex
        schemas.append(schema)
        server = start_server(schema)
        source = args.output / "source.sqlite"
        actor("acquire", source)
        for identity in ["a", "b", "c"]:
            actor("mutate", source, identity=identity)
        for point in ["bootstrap_before_commit", "bootstrap_after_commit"]:
            path = args.output / f"{point}.sqlite"
            actor("acquire", path)
            child = actor("bootstrap", path, point=point, wait=False)
            child.wait_for("BARRIER:" + point)
            child.finish(kill=True)
            assert local(path, "SELECT count(*) FROM titect_bootstrap")[0][0] == int(
                point == "bootstrap_after_commit"
            )
            assert local(path, "SELECT count(*) FROM fixture_checkpoints")[0][0] == 0
            actor("bootstrap", path)
            assert (
                local(path, "SELECT session_id FROM titect_bootstrap")[0][0] == schema
            )
            actor("sync", path)
            assert local(path, "SELECT count(*) FROM fixture_tasks")[0][0] == 3
            actor("expire", path)
            report["scenarios"].append({"name": point, "passed": True})

        for point in [
            "page_during_apply",
            "page_before_commit",
            "page_after_commit",
            "checkpoint_before_commit",
            "checkpoint_after_commit",
        ]:
            path = args.output / f"{point}.sqlite"
            actor("acquire", path)
            child = actor("sync", path, point=point, wait=False)
            child.wait_for("BARRIER:" + point)
            child.finish(kill=True)
            before_commit = point in {"page_during_apply", "page_before_commit"}
            assert local(path, "SELECT count(*) FROM fixture_tasks")[0][0] == (
                0 if before_commit else 2
            )
            checkpoints = local(path, "SELECT checkpoint FROM fixture_checkpoints")
            assert len(checkpoints) == int(point == "checkpoint_after_commit")
            for (checkpoint,) in checkpoints:
                proof = json.loads(checkpoint)["proof"]
                assert (
                    local(
                        path,
                        "SELECT count(*) FROM titect_pages WHERE proof=?",
                        (proof,),
                    )[0][0]
                    == 1
                )
            actor("sync", path)
            assert local(path, "SELECT count(*) FROM fixture_tasks")[0][0] == 3
            assert local(path, "SELECT count(*) FROM titect_shadow")[0][0] == 3
            actor("expire", path)
            report["scenarios"].append(
                {"name": point, "passed": True, "reopenedRows": 3}
            )

        for point, revoke in [
            ("page_before_apply", "acquire"),
            ("checkpoint_before_commit", "acquire"),
            ("checkpoint_before_commit", "expire"),
        ]:
            path = args.output / f"fence-{point}-{revoke}.sqlite"
            actor("acquire", path)
            child = actor("sync", path, point=point, wait=False)
            child.wait_for("BARRIER:" + point)
            actor(revoke, path, owner="replacement")
            child.resume()
            assert child.finish(success=False) != 0
            assert local(path, "SELECT count(*) FROM fixture_checkpoints")[0][0] == 0
            if point == "page_before_apply":
                assert local(path, "SELECT count(*) FROM fixture_tasks")[0][0] == 0
            actor("expire", path)
            report["scenarios"].append(
                {"name": f"fencing/{point}/{revoke}", "passed": True}
            )

        path = args.output / "storage-failure.sqlite"
        actor("acquire", path)
        local(
            path,
            "CREATE TRIGGER fail_apply BEFORE INSERT ON fixture_tasks BEGIN SELECT RAISE(FAIL, 'injected storage failure'); END",
        )
        failed = actor("sync", path, success=False)
        assert failed.process.returncode != 0
        assert local(path, "SELECT count(*) FROM fixture_checkpoints")[0][0] == 0
        assert local(path, "SELECT count(*) FROM titect_shadow")[0][0] == 0
        local(path, "DROP TRIGGER fail_apply")
        actor("sync", path)
        actor("expire", path)
        report["scenarios"].append({"name": "storage-failure-rollback", "passed": True})

        path = args.output / "pending.sqlite"
        actor("acquire", path)
        child = actor(
            "mutate",
            path,
            point="local_after_commit",
            identity="a",
            extra=("99",),
            wait=False,
        )
        child.wait_for("BARRIER:local_after_commit")
        child.finish(kill=True)
        actor("sync", path)
        assert local(path, "SELECT title,status FROM fixture_tasks WHERE id='a'")[
            0
        ] == ("99", "pending")
        assert local(path, "SELECT value FROM titect_shadow WHERE id='a'")[0][0] == "7"
        actor("cleanup", path)
        assert (
            local(path, "SELECT count(*) FROM fixture_outbox WHERE status='pending'")[
                0
            ][0]
            == 1
        )
        failed = actor("sync", path, extra=("expired",), success=False)
        assert failed.process.returncode != 0
        actor("expire", path)
        actor("expire", source)
        storm_path = args.output / "storm.sqlite"
        actor("acquire", storm_path)
        storm = actor("storm", storm_path)
        storm_results = [
            json.loads(line.removeprefix("STORM:"))
            for line in storm.lines
            if line.startswith("STORM:")
        ]
        assert len(storm_results) == 1
        metrics = storm_results[0]
        assert metrics["offered"] == len(metrics["outcomes"]) == 30
        assert {row["role"] for row in metrics["outcomes"]} == {
            "refresh",
            "reconnect",
            "outbox",
            "background",
        }
        assert 0 < metrics["maxConcurrent"] <= 2 and 0 < metrics["maxQueue"] <= 4
        assert metrics["attempts"] <= 30 and metrics["refused"] > 0
        actor("expire", storm_path)
        report["storm"] = metrics
        report["scenarios"].append({"name": "paired-storm", "passed": True})

        web_evidence = args.output / "web.json"
        web_run = run_captured(
            ["dart", "run", "tool/run_drift_web_fixture.dart", "--titect-recovery"],
            cwd=ROOT,
            env=dict(
                os.environ,
                TITECT_HTTP_ENDPOINT=f"http://127.0.0.1:{args.port}",
                TITECT_WEB_EVIDENCE=str(web_evidence.resolve()),
            ),
            timeout=240,
        )
        (args.output / "web.log").write_text(web_run.stdout + web_run.stderr)
        if web_run.returncode:
            raise ValueError("persistent Chrome recovery failed; see web.log")
        web_report = json.loads(web_evidence.read_text())
        assert (
            web_report["status"] == "passed"
            and web_report["browserClosed"]
            and web_report["serverClosed"]
        )
        assert {row["profile"] for row in web_report["profiles"]} == {
            "portable",
            "isolated",
        }
        report["web"] = web_report
        report["webSha256"] = digest(web_evidence.read_bytes())
        report["scenarios"].append(
            {"name": "persistent-chrome-recovery", "passed": True}
        )
        server.finish(terminate=True)
        report["scenarios"].append(
            {"name": "pending-shadow-retention-and-expired-cursor", "passed": True}
        )
        schema = "titect_" + uuid.uuid4().hex
        schemas.append(schema)
        streams.append(schema)
        server = start_server(schema, exact=True)
        path = args.output / "exact.sqlite"
        actor("acquire", path)
        actor("bootstrap-integrity", path)
        assert (
            local(path, "SELECT integrity FROM titect_bootstrap")[0][0]
            == "integrity-sha-256-exact-json-v1"
        )
        actor("exact-mutate", path, identity="exact-item")
        actor("sync", path)
        wire, response = local(path, "SELECT wire,response FROM titect_exact")[0]
        assert bytes(wire) == bytes(response)
        deadline = time.monotonic() + 20
        while True:
            with psycopg.connect(dsn) as connection:
                row = connection.execute(
                    sql.SQL("SELECT sent,received FROM {}.exact_bytes").format(
                        sql.Identifier(schema)
                    )
                ).fetchone()
                outbox = connection.execute(
                    sql.SQL("SELECT payload,delivered_at FROM {}.exact_outbox").format(
                        sql.Identifier(schema)
                    )
                ).fetchone()
                completed = connection.execute(
                    sql.SQL(
                        "SELECT count(*) FROM {}.exact_inbox WHERE completed_at IS NOT NULL"
                    ).format(sql.Identifier(schema))
                ).fetchone()[0]
            if row[1] is not None and outbox[1] is not None and completed == 1:
                break
            if time.monotonic() >= deadline:
                raise ValueError("exact PostgreSQL/JetStream drain did not complete")
            time.sleep(0.05)
        assert bytes(row[0]) == bytes(row[1]) == bytes(outbox[0]) == bytes(wire)
        assert (
            local(path, "SELECT title FROM fixture_tasks")[0][0]
            == "1.00000000000000001"
        )
        report["scenarios"].append(
            {
                "name": "exact-number-persistence",
                "passed": True,
                "wireSha256": digest(bytes(wire)),
                "wireBytes": len(wire),
                "postgresOutboxInboxReconciled": True,
            }
        )

        def persistent_state():
            return {
                table: local(path, f"SELECT * FROM {table} ORDER BY 1")
                for table in (
                    "fixture_tasks",
                    "fixture_checkpoints",
                    "titect_pages",
                    "titect_shadow",
                    "titect_bootstrap",
                    "titect_exact",
                )
            }

        before = persistent_state()
        for fault, name in [
            ("corrupt", "corrupted-page-rejection"),
            ("mismatch", "negotiated-policy-mismatch"),
            ("missing", "integrity-failure-state-and-checkpoint-unchanged"),
        ]:
            for _ in range(2):
                failed = actor("sync", path, point="integrity_" + fault, success=False)
                assert failed.process.returncode != 0
                assert any("wire/integrity" in line for line in failed.lines)
                assert persistent_state() == before
            report["scenarios"].append(
                {
                    "name": name,
                    "passed": True,
                    "reopened": True,
                    "stateAndCheckpointUnchanged": True,
                }
            )
        actor("expire", path)
        server.finish(terminate=True)
        exact_cleanup = [
            json.loads(line.removeprefix("EXACT_RESIDUAL:"))
            for line in server.lines
            if line.startswith("EXACT_RESIDUAL:")
        ]
        assert exact_cleanup == [{"tasks": 0, "natsConnections": 0}]
        report["exactTransportCleanup"] = exact_cleanup[0]
        django = run_captured(
            [args.django_python, "-m", "pytest", "-q"],
            cwd=args.python_root / "examples/django_reference",
            env=dict(
                os.environ,
                REFERENCE_POSTGRES_DSN=dsn,
                PYTHONPATH=str(args.python_root / "src"),
            ),
            timeout=120,
        )
        (args.output / "django.log").write_text(django.stdout + django.stderr)
        if django.returncode:
            raise ValueError("persistent Django compatibility failed; see django.log")
        report["scenarios"].append(
            {"name": "django-persistent-mutations", "passed": True}
        )
        report["durationSeconds"] = time.monotonic() - started
        execution_reference(
            args.python_root, pin, report["preliminary"], args.output / "reference.json"
        )
        if digest(args.actor.read_bytes()) != report["nativeActorSha256"]:
            raise ValueError("native actor changed during execution")
        report["status"] = "passed"
    except (Exception, KeyboardInterrupt) as error:
        report["error"] = f"{type(error).__name__}: {error}"
    finally:
        cleanup_errors = []
        for child in children:
            if child.process.poll() is None:
                try:
                    child.finish(kill=True, success=False)
                except Exception as error:
                    cleanup_errors.append(f"child cleanup: {type(error).__name__}")
        if streams:
            import asyncio

            import nats

            async def cleanup_streams():
                client = await nats.connect(
                    os.environ["TITECT_NATS_URL"],
                    connect_timeout=3,
                    allow_reconnect=False,
                )
                try:
                    for name in streams:
                        await client.jetstream().delete_stream(name)
                finally:
                    await client.close()

            try:
                asyncio.run(cleanup_streams())
            except Exception as error:
                cleanup_errors.append(f"broker cleanup: {type(error).__name__}")
        remaining = 0
        if schemas:
            try:
                with psycopg.connect(dsn, autocommit=True) as connection:
                    for schema in schemas:
                        remaining += connection.execute(
                            "SELECT count(*) FROM pg_stat_activity WHERE application_name=%s",
                            (schema,),
                        ).fetchone()[0]
                        connection.execute(
                            sql.SQL("DROP SCHEMA IF EXISTS {} CASCADE").format(
                                sql.Identifier(schema)
                            )
                        )
            except Exception as error:
                cleanup_errors.append(f"database cleanup: {type(error).__name__}")
        actor_residuals = [
            json.loads(line.removeprefix("RESIDUAL:"))
            for child in children
            for line in child.lines
            if line.startswith("RESIDUAL:") and '"running"' in line
        ]
        leases = 0
        for path in args.output.glob("*.sqlite"):
            try:
                leases += local(
                    path,
                    "SELECT count(*) FROM titect_authority WHERE expires_ms > CAST(unixepoch('subsec')*1000 AS INTEGER)",
                )[0][0]
            except Exception as error:
                cleanup_errors.append(f"authority inspection: {type(error).__name__}")
        if cleanup_errors:
            report["cleanupErrors"] = cleanup_errors
            report["status"] = "failed"
        report["maxima"] = {
            "running": max((row["peakRunning"] for row in actor_residuals), default=0),
            "queued": max((row["peakQueued"] for row in actor_residuals), default=0),
            "attempts": max((row["attempts"] for row in actor_residuals), default=0),
        }
        report["maxima"].update(
            {
                "admittedBytes": max(
                    (row["admittedBytes"] for row in actor_residuals), default=0
                ),
                "appliedPages": max(
                    (row["appliedPages"] for row in actor_residuals), default=0
                ),
                "retainedRows": max(
                    (row["retainedRows"] for row in actor_residuals), default=0
                ),
                "elapsedMicros": max(
                    (row["elapsedMicros"] for row in actor_residuals), default=0
                ),
            }
        )
        server_residuals = [
            json.loads(line.removeprefix("RESIDUAL:"))
            for child in children
            for line in child.lines
            if line.startswith("RESIDUAL:") and '"active"' in line
        ]
        report["serverMaxima"] = {
            "active": max((row["peakActive"] for row in server_residuals), default=0),
            "connections": max(
                (row["peakConnections"] for row in server_residuals), default=0
            ),
        }
        if (
            report["serverMaxima"]["active"] > 2
            or report["serverMaxima"]["connections"] > 2
        ):
            report["status"] = "failed"
            report["error"] = "server admission exceeded bounds"
        report["residualResources"] = {
            "childProcesses": sum(child.process.poll() is None for child in children),
            "postgresConnections": remaining,
            "activeAuthorities": leases,
            "runningTasks": sum(row["running"] for row in actor_residuals),
            "queuedTasks": sum(row["queued"] for row in actor_residuals),
            "openDatabases": sum(not row["databaseClosed"] for row in actor_residuals),
            "openHttpClients": sum(
                not row["httpClientClosed"] for row in actor_residuals
            ),
        }
        if any(report["residualResources"].values()):
            report["status"] = "failed"
            report["error"] = "owned resources remain after child termination"
        report["unverified"] = (
            [] if report["status"] == "passed" else ["acceptance-incomplete-see-error"]
        )
        data = json.dumps(report, indent=2, sort_keys=True).encode() + b"\n"
        (args.output / "recovery.json").write_bytes(data)
        (args.output / "recovery.sha256").write_text(digest(data) + "  recovery.json\n")
        print(data.decode())
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
