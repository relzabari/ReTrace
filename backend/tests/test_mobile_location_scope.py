"""Exercise the mobile store's SQL isolation without requiring the Flutter SDK."""

import re
import sqlite3
from pathlib import Path


def test_mobile_pending_and_acknowledgement_are_bound_to_account_and_session():
    source = (
        Path(__file__).resolve().parents[2]
        / "mobile/lib/data/local_location_store.dart"
    ).read_text()
    connection = sqlite3.connect(":memory:")
    # Model a v2 upgrade: pre-upgrade rows have no verifiable owner/session.
    ddl = re.search(r"CREATE TABLE location_points\([\s\S]*?\n          \)", source)[0]
    legacy_ddl = ddl.replace("user_id TEXT NOT NULL,", "").replace(
        "device_session_id TEXT NOT NULL,", ""
    )
    connection.execute(legacy_ddl)
    connection.execute(
        "INSERT INTO location_points (exercise_id,sequence_number,captured_at,latitude,longitude) VALUES ('e',1,'now',32,35)"
    )
    for statement in re.findall(
        r"db.execute\('(ALTER TABLE location_points ADD COLUMN (?:user_id|device_session_id) TEXT)'\)",
        source,
    ):
        connection.execute(statement)
    for sequence, user, session in [
        (2, "alice", "a1"),
        (3, "bob", "b1"),
        (4, "alice", "a2"),
    ]:
        connection.execute(
            "INSERT INTO location_points (exercise_id,user_id,device_session_id,sequence_number,captured_at,latitude,longitude) VALUES ('e',?,?,?,'now',32,35)",
            (user, session, sequence),
        )
    pending_where = re.search(r"where: '([^']+)'", source)[1]
    rows = connection.execute(
        "SELECT sequence_number FROM location_points WHERE " + pending_where,
        ("e", "alice", "a1", "PENDING"),
    ).fetchall()
    assert rows == [(2,)]
    update_method = source.split("Future<void> markSynced")[1]
    fragments = re.findall(r"'([^']*)'", update_method)
    update = next(value for value in fragments if value.startswith("UPDATE "))
    update += next(value for value in fragments if value.startswith("WHERE "))
    connection.execute(
        update.replace("$placeholders", "?,?,?,?"),
        ("SYNCED", "e", "alice", "a1", 1, 2, 3, 4),
    )
    assert connection.execute(
        "SELECT sequence_number FROM location_points WHERE sync_status='SYNCED'"
    ).fetchall() == [(2,)]
    # Both counters use the same account/session scope as pending uploads.
    for method in ["pendingCount", "totalCount"]:
        block = source.split("Future<int> " + method)[1].split("Future<")[0]
        assert "user_id = ? AND device_session_id = ?" in block
        assert "[exerciseId, userId, deviceSessionId]" in block
    connection.close()
