"""Durable device identities. The HTTP service only reads authorization state."""

import hashlib
import sqlite3
import time
import uuid
from collections.abc import Callable
from contextlib import contextmanager
from pathlib import Path

MAX_REGISTERED_DEVICES = 5

SCHEMA = """
CREATE TABLE IF NOT EXISTS devices (
    device_id TEXT PRIMARY KEY,
    public_key BLOB NOT NULL UNIQUE,
    device_name TEXT NOT NULL,
    registered_at INTEGER NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('active', 'revoking', 'revoked')),
    wifi_credential_id TEXT NOT NULL UNIQUE,
    token_hash BLOB NOT NULL UNIQUE,
    last_seen INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS settings (name TEXT PRIMARY KEY, value INTEGER NOT NULL);
INSERT OR IGNORE INTO settings VALUES ('registration_enabled', 1);
CREATE TABLE IF NOT EXISTS audit (
    id INTEGER PRIMARY KEY,
    occurred_at INTEGER NOT NULL,
    device_id TEXT NOT NULL,
    event TEXT NOT NULL
);
"""


def token_hash(token: str) -> bytes:
    return hashlib.sha256(token.encode("ascii")).digest()


class Registry:
    def __init__(self, database: Path) -> None:
        self.database = database

    @contextmanager
    def connection(self, *, read_only: bool = False):
        uri = self.database.resolve().as_uri() + ("?mode=ro" if read_only else "?mode=rw")
        connection = sqlite3.connect(uri, uri=True, timeout=3)
        connection.row_factory = sqlite3.Row
        try:
            with connection:
                yield connection
        finally:
            connection.close()

    def initialize(self) -> None:
        self.database.touch(mode=0o640, exist_ok=True)
        with self.connection() as connection:
            connection.executescript(SCHEMA)

    def activate(
        self, public_key: bytes, name: str, *, register: bool,
        issue_token: Callable[[str], str], enable_wifi: Callable[[str], None],
    ) -> sqlite3.Row:
        with self.connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute("SELECT * FROM devices WHERE public_key = ?", (public_key,)).fetchone()
            now = int(time.time())
            if row is not None:
                if row["status"] != "active":
                    raise ValueError("Device authorization is inactive")
                return row
            enabled = connection.execute("SELECT value FROM settings WHERE name = 'registration_enabled'").fetchone()[0]
            if not register or not enabled:
                raise ValueError("New device registration is closed")
            # BEGIN IMMEDIATE serializes competing registrations. Revoking
            # devices occupy a slot until their hotspot credential is disabled.
            registered = connection.execute(
                "SELECT COUNT(*) FROM devices WHERE status IN ('active', 'revoking')"
            ).fetchone()[0]
            if registered >= MAX_REGISTERED_DEVICES:
                raise ValueError(f"Maximum of {MAX_REGISTERED_DEVICES} phones may be registered")
            device_id, wifi_id = uuid.uuid4().hex, uuid.uuid4().hex
            enable_wifi(wifi_id)
            connection.execute(
                "INSERT INTO devices VALUES (?, ?, ?, ?, 'active', ?, ?, ?)",
                (device_id, public_key, name, now, wifi_id, token_hash(issue_token(device_id)), now),
            )
            connection.execute("INSERT INTO audit(occurred_at, device_id, event) VALUES (?, ?, 'register')", (now, device_id))
            return connection.execute("SELECT * FROM devices WHERE device_id = ?", (device_id,)).fetchone()

    def authorize(self, token: str) -> str | None:
        if len(token) != 43 or not token.isascii():
            return None
        with self.connection(read_only=True) as connection:
            row = connection.execute(
                "SELECT device_id FROM devices WHERE token_hash = ? AND status = 'active'", (token_hash(token),)
            ).fetchone()
            return row[0] if row else None

    def is_active(self, device_id: str) -> bool:
        with self.connection(read_only=True) as connection:
            return connection.execute(
                "SELECT 1 FROM devices WHERE device_id = ? AND status = 'active'", (device_id,)
            ).fetchone() is not None

    def list_devices(self) -> list[dict]:
        with self.connection(read_only=True) as connection:
            return [dict(row) for row in connection.execute(
                "SELECT device_id, device_name, registered_at, status, wifi_credential_id, last_seen FROM devices ORDER BY registered_at"
            )]

    def allow_registration(self, enabled: bool) -> None:
        with self.connection() as connection:
            connection.execute("UPDATE settings SET value = ? WHERE name = 'registration_enabled'", (int(enabled),))

    def revoke(self, device_id: str, disable_wifi: Callable[[str], None]) -> bool:
        with self.connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute("SELECT status, wifi_credential_id FROM devices WHERE device_id = ?", (device_id,)).fetchone()
            if row is None:
                return False
            if row["status"] == "revoked":
                return True
            if row["status"] == "active":
                connection.execute("UPDATE devices SET status = 'revoking' WHERE device_id = ?", (device_id,))
                connection.execute("INSERT INTO audit(occurred_at, device_id, event) VALUES (?, ?, 'revoke requested')", (int(time.time()), device_id))
        # Deny BLE and HTTPS before asking the hotspot to detach the station.
        disable_wifi(row["wifi_credential_id"])
        with self.connection() as connection:
            count = connection.execute("UPDATE devices SET status = 'revoked' WHERE device_id = ? AND status = 'revoking'", (device_id,)).rowcount
            if count:
                connection.execute("INSERT INTO audit(occurred_at, device_id, event) VALUES (?, ?, 'revoke completed')", (int(time.time()), device_id))
        return True
