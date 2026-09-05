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

from run_titect_conformance import (
    FIXTURE,
    ROOT,
    digest,
    evidence_identity,
    git,
    verify_reference,
)


class Child:
    def __init__(self, args, log, env=None):
        self.process = subprocess.Popen(
            args,
            cwd=ROOT,
            env=env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
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
            self.process.kill()
        elif terminate and self.process.poll() is None:
            self.process.terminate()
        try:
            code = self.process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            self.process.kill()
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
    import psycopg
    from psycopg import sql

    parser = argparse.ArgumentParser()
    parser.add_argument("--python-root", type=Path, required=True)
    parser.add_argument("--actor", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--port", type=int, default=55439)
    parser.add_argument("--preliminary", action="store_true")
    parser.add_argument("--django-python", default=sys.executable)
    args = parser.parse_args()
    args.python_root = args.python_root.resolve()
    args.actor = args.actor.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    dsn = os.environ["TITECT_POSTGRES_DSN"]
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
    serial = 0

    def start_server(schema, point=""):
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
            ],
            args.output / f"server-{serial}.log",
        )
        children.append(child)
        child.wait_for("READY")
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
        if sys.flags.optimize:
            raise ValueError("recovery assertions require Python optimization disabled")
        verify_reference(args.python_root.resolve(strict=True), pin, args.preliminary)
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
        web_run = subprocess.run(
            ["dart", "run", "tool/run_drift_web_fixture.dart", "--titect-recovery"],
            cwd=ROOT,
            env=dict(
                os.environ,
                TITECT_HTTP_ENDPOINT=f"http://127.0.0.1:{args.port}",
                TITECT_WEB_EVIDENCE=str(web_evidence.resolve()),
            ),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=240,
        )
        (args.output / "web.log").write_text(web_run.stdout)
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
        django = subprocess.run(
            [args.django_python, "-m", "pytest", "-q"],
            cwd=args.python_root / "examples/django_reference",
            env=dict(
                os.environ,
                REFERENCE_POSTGRES_DSN=dsn,
                PYTHONPATH=str(args.python_root / "src"),
            ),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=120,
        )
        (args.output / "django.log").write_text(django.stdout)
        if django.returncode:
            raise ValueError("persistent Django compatibility failed; see django.log")
        report["scenarios"].append(
            {"name": "django-persistent-mutations", "passed": True}
        )
        report["durationSeconds"] = time.monotonic() - started
        report["status"] = "passed"
    except Exception as error:
        report["error"] = f"{type(error).__name__}: {error}"
    finally:
        for child in children:
            if child.process.poll() is None:
                child.finish(kill=True, success=False)
        remaining = 0
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
        actor_residuals = [
            json.loads(line.removeprefix("RESIDUAL:"))
            for child in children
            for line in child.lines
            if line.startswith("RESIDUAL:") and '"running"' in line
        ]
        leases = sum(
            local(
                path,
                "SELECT count(*) FROM titect_authority WHERE expires_ms > CAST(unixepoch('subsec')*1000 AS INTEGER)",
            )[0][0]
            for path in args.output.glob("*.sqlite")
        )
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
