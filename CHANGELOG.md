# Changelog

All notable changes to `remote` are documented in this file.

## [0.6.0] - 2026-09-14 - Wave mu-05 audit + encaps parity (remote#8)

### Audit finding

Wave mu-05's project-wide plan described this repo's `src/kem.pdx` as
"currently WEAK deterministic-key stub" needing to be "replace[d]
with real paideia_crypto_ml_kem_768_keypair/encaps/decaps intrinsic
calls". That characterization was already stale: remote#2 (v0.5.0)
had already landed REAL kernel-linked `MlKem768::keygen`/`::decaps`
trait calls (`kem_keygen_raw`/`kem_decaps_raw`) -- not a deterministic
stub. No client-side key-generation or decapsulation code needed
replacing.

### Added

- **`kem_encaps_raw(ek_ptr, seed_m_ptr, ct_out_ptr, ss_out_ptr)`**
  (`src/kem.pdx`) -- a real `MlKem768::encaps` trait-call wrapper, for
  parity with the pre-existing `kem_keygen_raw`/`kem_decaps_raw` and
  fulfilling this file's own forward-reference to a future `remoted`
  daemon's server-role needs. Still unused by `remote`/`rcopy`'s
  client-only binaries (encapsulation is the SERVER's step in this
  protocol shape) -- exported so a future daemon module has an
  already-proven call surface.

### Known gaps (unchanged)

- Seed entropy (`kem_fill_seed_bytes`) still derives from an
  `rdtsc`-mixed splitmix64-adjacent avalanche, NOT a CSPRNG -- no
  `SecureRandom`/`rdrand`/`rdseed` primitive exists in the paideia-as
  stdlib or encoder as of this audit. This remains the one real
  security gap in the KEM path (tracked since remote#2); everything
  else in the handshake (keygen, encaps trait declaration, decaps) now
  runs through real kernel-linked intrinsics.

### Also included (R85 closure, previously unreleased)

- **remote#6** (M1-006): connection-success fingerprint. `src/kem.pdx`
  gains `kem_hex_nibble` / `kem_hash_to_hex8` / `kem_peer_key_hash64`
  (Jenkins one-at-a-time, non-cryptographic -- no hash primitive is
  linked yet) / `kem_peer_key_fingerprint_hex`. `RemoteClient::_start`
  emits `remote ok host=<H> peer_key=<hex8>\n` to fd 2 right after
  `kem_client_handshake` succeeds, hashing `kem_ek` (the only ML-KEM
  public key material available client-side in this protocol shape --
  see README.md design note).
- **remote#7** (M1-008): round closure -- `STATUS.md` +
  `design/round-retrospectives/r85-closure.md`; `r85-closed` tag.

## [0.5.0] - 2026-09-13

Wave SS 5-issue cohort -- initial landing of the whole M1 milestone in
one tagged commit.

- **remote#1** (M1-001): repo bootstrap -- README.md, LICENSE (MIT),
  CHANGELOG.md, caps.decl (`KIND_USER` + `KIND_TCP_SOCKET` narrowed to
  `connect` + `KIND_TTY` + `KIND_PDXFS_FILE`), tools/build.sh,
  manifest.pdxsig (source-form, unsigned).
- **remote#2** (M1-002): `src/kem.pdx` (`Module Kem`) -- ML-KEM-768 key
  exchange over TCP using paideia-as's kernel-linked `MlKem768`
  intrinsics. Client generates an ephemeral keypair, sends the
  1184-byte encapsulation key, receives a 1088-byte ciphertext, and
  decapsulates a 32-byte shared secret.
- **remote#3** (M1-003): `src/channel.pdx` (`Module Channel`) -- a
  ChaCha20-Poly1305 AEAD framed channel over the KEM session key, using
  paideia-as's kernel-linked `ChaCha20Poly1305` intrinsics. Per-frame:
  12-byte counter nonce, plaintext payload, 16-byte tag, 4-byte
  big-endian length prefix.
- **remote#4** (M1-004): `src/remote_client.pdx` (`Module RemoteClient`)
  -- `remote <host>` binary. TCP connect to `<host>:22`, KEM handshake,
  channel wrap, `AUTH_CHALLENGE` / `SPAWN_SHELL` opcodes, local tty
  raw-mode bridge (stdin -> channel -> stdout pump).
- **remote#5** (M1-005): `src/rcopy.pdx` (`Module Rcopy`) --
  `rcopy <local> <host>:<remote>` binary. Same KEM+channel handshake;
  sends a `COPY` request record (`{op, name_len, name_bytes, size,
  sha256}`) then streams the source file in 4096-byte chunks, each
  acknowledged by the server.

Known gaps (see README.md "Known gaps at this landing"): KEM seed
entropy is `rdtsc`-derived (not cryptographically strong) pending a
linked CSPRNG intrinsic; `rcopy`'s `sha256` field is a documented
32-zero-byte stub pending a linked `Sha256` primitive; tty raw mode
fails closed pending a `KIND_TTY` loader-seed for non-shell processes;
`<host>` must be a dotted-quad IPv4 literal (no resolver syscall
exists yet).
