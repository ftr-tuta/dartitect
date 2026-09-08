"""Real Dart offered load against the pinned Python/PostgreSQL/JetStream fixture."""

import argparse
import asyncio
import json
import os
import socket
import sqlite3
import sys
import time
import uuid
from collections import Counter
from pathlib import Path
from urllib.error import URLError
from urllib.request import urlopen

from run_titect_conformance import (
    FIXTURE,
    cancel_on_termination,
    digest,
    evidence_identity,
    execution_reference,
    fresh_output,
    git,
    write_report,
)
from run_titect_recovery import Child

PARAMETERS = {
    "seed": 41,
    "offerSeconds": 2,
    "rates": [50, 400, 50],
    "offers": [100, 800, 100],
    "concurrency": 2,
    "queue": 4,
    "maxAttempts": 2400,
    "maxReceivedBytes": 8 * 1024 * 1024,
    "maxSentBytes": 8 * 1024 * 1024,
    "maxRetainedRecords": 800,
    "maxScopeSeconds": 22,
    "maxDrainSeconds": 20,
    "restartDelayMs": 200,
    "maxServerRssMiB": 512,
    "maxServerTasks": 100,
    "maxServerConnections": 8,
}
RESOURCES = {
    "activeAuthorities",
    "childProcesses",
    "openDatabases",
    "openHttpClients",
    "postgresConnections",
    "queuedTasks",
    "runningTasks",
}


def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[int((len(ordered) - 1) * fraction)]


def scenario(args, name, actor_sha):
    import nats
    import psycopg
    from psycopg import sql

    rate = 400 if name == "saturation" else 50
    schema = "titect_" + uuid.uuid4().hex
    children = []
    peaks = Counter()
    samples = []
    failures = []
    cleanup = None
    result = {"scenario": name, "passed": False, "failures": failures}
    server = actor = None
    serial = 0
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]
    endpoint = f"http://127.0.0.1:{port}"
    path = args.output / f"{name}.sqlite"

    def start():
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
                str(port),
                "--exact",
                "--delay",
                "0.03" if name != "offered" else "0",
            ],
            args.output / f"{name}.server-{serial}.log",
        )
        children.append(child)
        child.wait_for("READY")
        deadline = time.monotonic() + 10
        while True:
            try:
                with urlopen(endpoint + "/metrics", timeout=0.5) as response:
                    if response.status == 200:
                        break
            except (URLError, TimeoutError, ConnectionError):
                pass
            if time.monotonic() >= deadline:
                raise TimeoutError("capacity HTTP readiness deadline exceeded")
            time.sleep(0.02)
        return child

    def sample():
        try:
            with urlopen(endpoint + "/exact-metrics", timeout=0.5) as response:
                value = json.load(response)
            if not value["background_ok"]:
                raise ValueError("exact relay or consumer failed")
            for key in (
                "rss_kib",
                "tasks",
                "connections",
                "database_lock_waiters",
                "backlog_age_seconds",
            ):
                peaks[key] = max(peaks[key], value[key])
            if len(samples) >= 440:
                raise ValueError("capacity sample retention exceeded")
            samples.append({"elapsed_seconds": time.monotonic() - started, **value})
            return value
        except (URLError, TimeoutError, ConnectionError):
            return None

    try:
        server = start()
        actor = Child(
            [str(args.actor), "capacity", str(path), endpoint, name, "41", str(rate)],
            args.output / f"{name}.actor.log",
            executable_sha256=actor_sha,
        )
        children.append(actor)
        actor.wait_for("CAPACITY_READY")
        started = time.monotonic()
        deadline = started + 22
        crashed = False
        restart_ms = 0
        while actor.process.poll() is None:
            if name == "recovery" and not crashed and time.monotonic() - started >= 1:
                server.finish(kill=True)
                stopped = time.monotonic()
                time.sleep(0.2)
                restart_ms = (time.monotonic() - stopped) * 1000
                server = start()
                crashed = True
            sample()
            if time.monotonic() >= deadline:
                raise TimeoutError("finite Dart capacity scope exceeded")
            time.sleep(0.05)
        actor.finish()
        rows = [
            json.loads(line.removeprefix("CAPACITY:"))
            for line in actor.lines
            if line.startswith("CAPACITY:")
        ]
        if len(rows) != 1:
            raise ValueError("missing or duplicate Dart capacity measurements")
        native = rows[0]
        outcomes = native["outcomes"]
        write_report(args.output, f"{name}.offers", outcomes)
        write_report(args.output, f"{name}.native", native)
        statuses = Counter(row["status"] for row in outcomes)
        if (
            len(outcomes) != rate * 2
            or sorted(row["index"] for row in outcomes) != list(range(rate * 2))
            or len({row["id"] for row in outcomes}) != rate * 2
        ):
            failures.append("missing, duplicated or substituted Dart offers")
        if any(row["state"] in ("failed", "uncertain") for row in outcomes):
            failures.append("Dart offers contain unreconciled or failed outcomes")
        if (
            native["attempts"] > PARAMETERS["maxAttempts"]
            or native["receivedBytes"] > PARAMETERS["maxReceivedBytes"]
            or native["sentBytes"] > PARAMETERS["maxSentBytes"]
            or native["retainedRecords"] > 800
            or native["peakRunning"] > 2
            or native["peakQueued"] > 4
            or native["offerMicros"] < 2000000
            or native["elapsedMicros"] < native["offerMicros"]
            or native["elapsedMicros"] > 22000000
        ):
            failures.append("Dart scenario budget exceeded")
        if name == "recovery" and (
            not crashed or native["disconnects"] < 1 or native["reconnects"] < 1
        ):
            failures.append(
                "server crash and Dart disconnect/reconnect were not observed"
            )
        drain_start = time.monotonic()
        last = None
        while time.monotonic() < deadline:
            last = sample()
            if (
                last
                and last["durable"]["pending_outbox"] == 0
                and last["durable"]["receipts"] == last["durable"]["inbox"]
            ):
                break
            time.sleep(0.05)
        else:
            raise TimeoutError("outbox/inbox did not reconcile within the finite drain")
        recovery_seconds = time.monotonic() - drain_start
        if (
            recovery_seconds > 20
            or native["elapsedMicros"] / 1000000 + recovery_seconds > 22
        ):
            failures.append("finite offer and drain interval exceeded")
        with sqlite3.connect(path) as local:
            local_rows = {
                row[0]: (
                    bytes(row[1]),
                    None if row[2] is None else bytes(row[2]),
                    row[3],
                )
                for row in local.execute(
                    "SELECT id,wire,response,state FROM capacity_offers"
                )
            }
        with psycopg.connect(os.environ["TITECT_POSTGRES_DSN"]) as connection:
            remote = connection.execute(
                sql.SQL("SELECT identity,sent,received FROM {}.exact_bytes").format(
                    sql.Identifier(schema)
                )
            ).fetchall()
            payloads = connection.execute(
                sql.SQL("SELECT message_id,payload FROM {}.exact_outbox").format(
                    sql.Identifier(schema)
                )
            ).fetchall()
            receipts = connection.execute(
                sql.SQL("SELECT receipt_id,result FROM {}.receipt").format(
                    sql.Identifier(schema)
                )
            ).fetchall()
        committed = {row["id"] for row in outcomes if row["state"] == "committed"}
        if (
            committed != {row[0] for row in remote}
            or len(local_rows) != native["retainedRecords"]
        ):
            failures.append("Dart and PostgreSQL committed identities differ")
        for identity, sent, received in remote:
            original, response, state = local_rows[identity]
            if (
                original != response
                or original != bytes(sent)
                or original != bytes(received)
                or state != "committed"
            ):
                failures.append("Drift/PostgreSQL/JetStream exact bytes differ")
        for identity, payload in payloads:
            if bytes(payload) != local_rows[identity][0]:
                failures.append("PostgreSQL outbox bytes differ from Dart")
        for identity, payload in receipts:
            if bytes(payload) != local_rows[identity.removeprefix("exact:")][0]:
                failures.append("receipt bytes differ from Dart")
        durable = last["durable"]
        if (
            durable["inbox"] <= 0
            or durable["receipts"] != durable["outbox"]
            or durable["outbox"] != durable["inbox"]
            or durable["inbox"] != len(committed)
            or durable["byte_mismatches"]
            or durable["pending_outbox"]
        ):
            failures.append("durable counts or bytes do not reconcile")
        if not (
            0 < peaks["rss_kib"] <= 512 * 1024
            and 0 < peaks["tasks"] <= 100
            and peaks["connections"] <= 8
        ):
            failures.append("existing server resource budget exceeded")
        latencies = [row["latencyMicros"] / 1000000 for row in outcomes]
        duration = native["elapsedMicros"] / 1000000
        write_report(args.output, f"{name}.samples", samples)
        result.update(
            {
                "seed": 41,
                "offered": len(outcomes),
                "statuses": dict(statuses),
                "duration_seconds": duration,
                "useful_operations": durable["inbox"],
                "useful_throughput": durable["inbox"] / (duration + recovery_seconds),
                "latency_seconds": {
                    "p50": percentile(latencies, 0.5),
                    "p95": percentile(latencies, 0.95),
                    "p99": percentile(latencies, 0.99),
                    "max": max(latencies),
                },
                "peak_observations": dict(peaks),
                "recovery_seconds": recovery_seconds,
                "durable": durable,
                "load_generator": {
                    "workers": 2,
                    "queue_capacity": 4,
                    "offered_rate": rate,
                },
                "client": {
                    key: value for key, value in native.items() if key != "outcomes"
                },
                "restart_delay_ms": restart_ms,
                "artifacts": {
                    f"{name}.{kind}.json": digest(
                        (args.output / f"{name}.{kind}.json").read_bytes()
                    )
                    for kind in ("offers", "native", "samples")
                },
            }
        )
    except (Exception, KeyboardInterrupt) as error:
        failures.append(f"{type(error).__name__}: {error}")
    finally:
        for child in children:
            if child.process.poll() is None:
                try:
                    child.finish(
                        kill=child is not server,
                        terminate=child is server,
                        success=False,
                    )
                except Exception as error:
                    failures.append(f"child cleanup: {type(error).__name__}: {error}")
        actor_cleanup = (
            []
            if actor is None
            else [
                json.loads(line.removeprefix("RESIDUAL:"))
                for line in actor.lines
                if line.startswith("RESIDUAL:")
            ]
        )
        transport_cleanup = (
            []
            if server is None
            else [
                json.loads(line.removeprefix("EXACT_RESIDUAL:"))
                for line in server.lines
                if line.startswith("EXACT_RESIDUAL:")
            ]
        )
        if len(actor_cleanup) != 1 or actor_cleanup[0] != {
            "running": 0,
            "queued": 0,
            "databaseClosed": True,
            "httpClientClosed": True,
        }:
            failures.append("Dart actor cleanup evidence is missing or nonzero")
        if transport_cleanup != [{"tasks": 0, "natsConnections": 0}]:
            failures.append(
                "Python exact transport cleanup evidence is missing or nonzero"
            )

        async def remove_stream():
            client = await nats.connect(
                os.environ["TITECT_NATS_URL"], connect_timeout=3, allow_reconnect=False
            )
            try:
                await client.jetstream().delete_stream(schema)
            finally:
                await client.close()

        try:
            asyncio.run(remove_stream())
        except Exception as error:
            failures.append(f"broker cleanup: {type(error).__name__}: {error}")
        try:
            with psycopg.connect(
                os.environ["TITECT_POSTGRES_DSN"], autocommit=True
            ) as connection:
                remaining = connection.execute(
                    "SELECT count(*) FROM pg_stat_activity WHERE application_name=%s",
                    (schema,),
                ).fetchone()[0]
                connection.execute(
                    sql.SQL("DROP SCHEMA IF EXISTS {} CASCADE").format(
                        sql.Identifier(schema)
                    )
                )
            cleanup = {
                "activeAuthorities": 0,
                "childProcesses": sum(
                    child.process.poll() is None for child in children
                ),
                "openDatabases": int(
                    not actor_cleanup or not actor_cleanup[0]["databaseClosed"]
                ),
                "openHttpClients": int(
                    not actor_cleanup or not actor_cleanup[0]["httpClientClosed"]
                ),
                "postgresConnections": remaining,
                "queuedTasks": sum(row["queued"] for row in actor_cleanup),
                "runningTasks": sum(row["running"] for row in actor_cleanup),
            }
            if any(cleanup.values()):
                failures.append("owned capacity resources remain")
        except Exception as error:
            failures.append(f"cleanup: {type(error).__name__}: {error}")
    result["residualResources"] = cleanup
    result["passed"] = not failures
    return result


def main():
    cancel_on_termination()
    parser = argparse.ArgumentParser()
    parser.add_argument("--python-root", type=Path, required=True)
    parser.add_argument("--actor", type=Path, required=True)
    parser.add_argument("--reference-manifest", type=Path)
    parser.add_argument("--preliminary", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.python_root = args.python_root.resolve()
    args.actor = args.actor.resolve()
    fresh_output(args.output)
    pin = json.loads((FIXTURE / "pin.json").read_text())
    report = {
        "schemaVersion": 1,
        "status": "failed",
        "releaseEligible": False,
        **evidence_identity(pin),
        "parameters": PARAMETERS,
        "results": [],
        "residualResources": None,
    }
    try:
        report["reference"] = execution_reference(
            args.python_root, pin, args.preliminary, args.reference_manifest
        )
        report["preliminary"] = report["reference"]["mode"] == "candidate"
        report["releaseEligible"] = not report["preliminary"]
        report["pythonSha"] = report["reference"]["pythonSha"]
        report["pythonMainSha"] = git(
            args.python_root, "rev-parse", "refs/remotes/origin/main"
        )
        write_report(args.output, "reference", report["reference"])
        report["referenceSha256"] = digest(
            (args.output / "reference.json").read_bytes()
        )
        report["nativeActorSha256"] = digest(args.actor.read_bytes())
        for name in ("offered", "saturation", "recovery"):
            report["results"].append(scenario(args, name, report["nativeActorSha256"]))
        execution_reference(
            args.python_root, pin, report["preliminary"], args.output / "reference.json"
        )
        if digest(args.actor.read_bytes()) != report["nativeActorSha256"]:
            raise ValueError("native actor changed during execution")
        if not all(row["passed"] for row in report["results"]):
            raise ValueError("capacity correctness, budgets or cleanup failed")
        report["residualResources"] = {
            key: sum(row["residualResources"][key] for row in report["results"])
            for key in RESOURCES
        }
        report["status"] = "passed"
    except (Exception, KeyboardInterrupt) as error:
        report["error"] = f"{type(error).__name__}: {error}"
    write_report(args.output, "capacity", report)
    print(json.dumps(report, indent=2, sort_keys=True))
    return int(report["status"] != "passed")


if __name__ == "__main__":
    raise SystemExit(main())
