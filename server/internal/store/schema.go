package store

const schema = `
CREATE TABLE IF NOT EXISTS users (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL UNIQUE,
  role       TEXT NOT NULL CHECK (role IN ('admin','member')),
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS devices (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  platform     TEXT NOT NULL,
  identity_key TEXT NOT NULL,
  token_hash   TEXT NOT NULL UNIQUE,
  fcm_token    TEXT,
  created_at   TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS devices_user ON devices(user_id);
CREATE TABLE IF NOT EXISTS invites (
  code       TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at TEXT NOT NULL,
  used_at    TEXT
);
CREATE TABLE IF NOT EXISTS envelopes (
  id          TEXT PRIMARY KEY,
  from_device TEXT NOT NULL,
  to_device   TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  nonce       BLOB NOT NULL,
  ciphertext  BLOB NOT NULL,
  created_at  TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS envelopes_to ON envelopes(to_device, created_at);
CREATE TABLE IF NOT EXISTS blobs (
  id           TEXT PRIMARY KEY,
  owner_device TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  size         INTEGER NOT NULL,
  chunk_size   INTEGER NOT NULL,
  complete     INTEGER NOT NULL DEFAULT 0,
  created_at   TEXT NOT NULL,
  expires_at   TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS blob_chunks (
  blob_id TEXT NOT NULL REFERENCES blobs(id) ON DELETE CASCADE,
  n       INTEGER NOT NULL,
  size    INTEGER NOT NULL,
  PRIMARY KEY (blob_id, n)
);
CREATE TABLE IF NOT EXISTS blob_recipients (
  blob_id   TEXT NOT NULL REFERENCES blobs(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,
  delivered INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (blob_id, device_id)
);
`
