"""Generate the same raw wire inputs for Python, Dart VM and Chrome."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def build_vectors():
    cases = []

    def add(name, profile, value, *, raw=False):
        cases.append(
            {
                "name": name,
                "profile": profile,
                "wire": value
                if raw
                else json.dumps(value, ensure_ascii=False, separators=(",", ":")),
            }
        )

    session = {
        "session_id": "s",
        "created_at": "2026-01-01T00:00:00.000Z",
        "expires_at": "2026-01-02T00:00:00.000Z",
    }
    dataset = {"dataset_id": "d", "generation": 7, "modes": ["snapshot", "delta"]}
    limits = {
        "max_document_bytes": 1048576,
        "max_datasets": 128,
        "max_items_per_page": 1000,
        "max_mutations": 1000,
        "max_opaque_id_bytes": 255,
        "max_capabilities": 32,
    }
    upsert = {"item_id": "i", "revision": 2, "value": {"enabled": True}}
    tombstone = {
        "item_id": "j",
        "revision": 3,
        "deleted_at": "2026-01-01T00:00:00.123Z",
    }
    integrity = {"algorithm": "sha-256", "digest": "a" * 64, "item_count": 1}
    outcome = {
        "mutation_id": "m",
        "state": "applied",
        "revision": 2,
        "receipt_id": "r",
        "reason": None,
    }
    payloads = {
        "session": session,
        "dataset": dataset,
        "bootstrap_request": {
            "client_id": "c",
            "dataset_ids": ["d"],
            "capabilities": ["delta"],
        },
        "bootstrap_response": {
            "session": session,
            "datasets": [dataset],
            "limits": limits,
        },
        "snapshot": {
            "dataset_id": "d",
            "generation": 7,
            "upserts": [upsert],
            "next_cursor": "opaque/+==?é",
            "integrity": integrity,
        },
        "delta": {
            "dataset_id": "d",
            "generation": 7,
            "upserts": [upsert],
            "tombstones": [tombstone],
            "next_cursor": None,
            "integrity": dict(integrity, item_count=2),
        },
        "reset_required": {"dataset_id": "d", "generation": 7, "reason": "expired"},
        "generation_mismatch": {"dataset_id": "d", "expected": 7, "actual": 8},
        "readiness": {
            "ready": False,
            "checked_at": "2026-01-01T00:00:00.123Z",
            "reason": "busy",
            "retry_after_ms": 1000,
        },
        "mutation_outcome": outcome,
        "mutation_outcomes": {
            "dataset_id": "d",
            "generation": 7,
            "outcomes": [outcome],
        },
    }

    def sync(name, kind, payload):
        add(
            name,
            "titect-sync/1",
            {"protocol": "titect-sync/1", "kind": kind, "payload": payload},
        )

    for kind, payload in payloads.items():
        sync(kind, kind, payload)
        for field in payload:
            missing = dict(payload)
            del missing[field]
            sync(f"{kind}/missing/{field}", kind, missing)
        sync(f"{kind}/extra", kind, dict(payload, future=True))
    for number in [
        -1,
        True,
        0,
        9007199254740991,
        9007199254740992,
        9007199254740993,
        18446744073709551617,
        10**1000,
    ]:
        sync(f"integer/{str(number)[:25]}", "dataset", dict(dataset, generation=number))
    dataset_wire = json.dumps(
        {"protocol": "titect-sync/1", "kind": "dataset", "payload": dataset},
        ensure_ascii=False,
        separators=(",", ":"),
    )
    for digits in [4300, 4301]:
        add(
            f"integer/python-digit-bound/{digits}",
            "titect-sync/1",
            dataset_wire.replace('"generation":7', '"generation":' + "9" * digits),
            raw=True,
        )
    for total in [1048576, 1048577]:
        add(f"wire/bytes/{total}", "titect-sync/1", dataset_wire, raw=True)
        # Neutral compact vector recipe; both targets append exactly this many
        # ASCII bytes. Avoid storing megabytes of whitespace in generated code.
        cases[-1]["appendSpaces"] = total - len(dataset_wire.encode())
    add("wire/utf8-bom", "titect-sync/1", "\ufeff" + dataset_wire, raw=True)
    snapshot_wire = json.dumps(
        {
            "protocol": "titect-sync/1",
            "kind": "snapshot",
            "payload": payloads["snapshot"],
        },
        ensure_ascii=False,
        separators=(",", ":"),
    )
    add(
        "wire/duplicate-allocation",
        "titect-sync/1",
        snapshot_wire.replace(
            '{"enabled":true}', "{" + ",".join(['"enabled":true'] * 10001) + "}"
        ),
        raw=True,
    )

    def nodes(value):
        if isinstance(value, dict):
            return 1 + sum(nodes(child) for child in value.values())
        if isinstance(value, list):
            return 1 + sum(nodes(child) for child in value)
        return 1

    empty = json.loads(snapshot_wire)
    empty["payload"]["upserts"][0]["value"] = []
    base = nodes(empty)
    for total in [10000, 10001]:
        value = json.loads(json.dumps(empty))
        value["payload"]["upserts"][0]["value"] = [0] * (total - base)
        add(f"wire/items/{total}", "titect-sync/1", value)
    for identifier in [
        "",
        " d",
        "d\n",
        "\u0085d",
        "d\u001f",
        "\ufeffd",
        "é" * 127,
        "é" * 128,
        "😀" * 63,
        "😀" * 64,
    ]:
        sync(f"id/{len(cases)}", "dataset", dict(dataset, dataset_id=identifier))
    for modes in [[], ["delta", "delta"], ["future"]]:
        sync(f"modes/{len(cases)}", "dataset", dict(dataset, modes=modes))
    for capabilities in [["future"], ["delta", "delta"], [str(i) for i in range(33)]]:
        sync(
            f"capabilities/{len(cases)}",
            "bootstrap_request",
            dict(payloads["bootstrap_request"], capabilities=capabilities),
        )
    for timestamp in [
        "0000-01-01T00:00:00.000Z",
        "2026-02-30T00:00:00.000Z",
        "2026-01-01T24:00:00.000Z",
        "2026-01-01T00:00:00Z",
        "2026-01-01T00:00:00.000+00:00",
        "2000-02-29T00:00:00.000Z",
    ]:
        sync(
            f"timestamp/{timestamp}",
            "readiness",
            dict(payloads["readiness"], checked_at=timestamp),
        )
    for state in ["rejected", "conflict", "uncertain", "future"]:
        sync(
            f"outcome/{state}",
            "mutation_outcome",
            dict(outcome, state=state, revision=None, reason="decision"),
        )
    for count in [0, 1, 2]:
        sync(
            f"integrity/count/{count}",
            "snapshot",
            dict(payloads["snapshot"], integrity=dict(integrity, item_count=count)),
        )
    # Both currently accept arbitrary correctly-shaped digest contents. Keep
    # this probe visible; it does not establish cryptographic page integrity.
    sync(
        "integrity/content-unverified",
        "snapshot",
        dict(payloads["snapshot"], integrity=dict(integrity, digest="b" * 64)),
    )
    for field, value in [("digest", "A" * 64), ("algorithm", "sha-512")]:
        sync(
            f"integrity/{field}",
            "snapshot",
            dict(payloads["snapshot"], integrity=dict(integrity, **{field: value})),
        )
    for count in [1000, 1001]:
        sync(
            f"page/items/{count}",
            "snapshot",
            dict(
                payloads["snapshot"],
                upserts=[upsert] * count,
                integrity=dict(integrity, item_count=count),
            ),
        )
    for depth in [25, 33]:
        value = 0
        for _ in range(depth):
            value = [value]
        sync(
            f"payload/depth/{depth}",
            "snapshot",
            dict(payloads["snapshot"], upserts=[dict(upsert, value=value)]),
        )
    for count in [16384, 16385]:
        sync(
            f"payload/string/{count}",
            "snapshot",
            dict(payloads["snapshot"], upserts=[dict(upsert, value="a" * count)]),
        )
    for kind, protocol in [("future", "titect-sync/1"), ("dataset", "titect-sync/2")]:
        add(
            f"unsupported/{kind}/{protocol}",
            "titect-sync/1",
            {"protocol": protocol, "kind": kind, "payload": dataset},
        )
    for profile in ["titect-sync/1", "titect-message/1"]:
        for raw in ["{", "{} extra", "NaN", '"\\ud800"', "[]"]:
            add(f"syntax/{profile}/{raw}", profile, raw, raw=True)

    message = json.loads(
        (ROOT / "bundles/titect-message/1/fixtures/positive/message.json").read_text()
    )
    add("message", "titect-message/1", message)
    for field in message:
        changed = dict(message)
        del changed[field]
        add(f"message/missing/{field}", "titect-message/1", changed)
    for field, value in [
        ("future", True),
        ("profile", "titect-message/2"),
        ("specversion", "2.0"),
        ("type", "1invalid"),
        ("correlationid", None),
    ]:
        add(
            f"message/invalid/{field}",
            "titect-message/1",
            dict(message, **{field: value}),
        )
    for token in [
        "9007199254740993",
        "0.1",
        "1.00000000000000001",
        "1e-7",
        "1e20",
        "-0.0",
        "1e-9999",
        "1e9999",
    ]:
        value = dict(message, data="NUMBER_TOKEN")
        wire = json.dumps(value, ensure_ascii=False, separators=(",", ":")).replace(
            '"NUMBER_TOKEN"', token
        )
        add(f"message/number/{token}", "titect-message/1", wire, raw=True)
    add(
        "message/unicode-order",
        "titect-message/1",
        dict(message, data={"😀": True, "\ue000": False}),
    )
    return cases


if __name__ == "__main__":
    import sys

    encoded = json.dumps(build_vectors(), ensure_ascii=True, indent=2) + "\n"
    dart = (
        "// Generated by generate_vectors.py; do not edit.\nconst titectVectorsJson = r'''"
        + encoded
        + "''';\n"
    )
    outputs = {ROOT / "vectors.json": encoded, ROOT / "vectors.g.dart": dart}
    if "--check" in sys.argv:
        if any(
            not path.exists() or path.read_text() != text
            for path, text in outputs.items()
        ):
            raise SystemExit("Titect vectors are stale")
    else:
        for path, text in outputs.items():
            path.write_text(text)
