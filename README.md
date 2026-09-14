# remote

Post-quantum-secured remote shell + file copy for PaideiaOS.

Two binaries, one source tree:

| Binary   | Entry point                      | Purpose |
|----------|-----------------------------------|---------|
| `remote` | `RemoteClient::_start` (src/remote_client.pdx) | `remote <host>` -- authenticate, spawn a remote shell, bridge the local tty to it. |
| `rcopy`  | `Rcopy::_start` (src/rcopy.pdx)   | `rcopy <local> <host>:<remote>` -- authenticate, stream a local file to a remote path. |

Both binaries share two library modules:

- `src/kem.pdx` (`Module Kem`) -- ML-KEM-768 (FIPS 203) key exchange over
  the raw TCP socket, using paideia-as's kernel-linked `MlKem768`
  intrinsics (`crates/paideia-as-stdlib/pdx/crypto/ml_kem_768.pdx`).
- `src/channel.pdx` (`Module Channel`) -- a ChaCha20-Poly1305 AEAD framed
  transport keyed by the KEM shared secret, using paideia-as's
  kernel-linked `ChaCha20Poly1305` intrinsics
  (`crates/paideia-as-stdlib/pdx/crypto/chacha20_poly1305.pdx`).

## Protocol shape (v0.5.0 / M1)

1. TCP connect to `<host>:22` (an SSH-shaped port; `remote` and `rcopy`
   share one daemon/port, dispatching by opcode rather than by port).
2. ML-KEM-768 handshake (`Kem::kem_client_handshake`): the client
   generates an ephemeral keypair, sends the 1184-byte encapsulation key,
   receives a 1088-byte ciphertext, and decapsulates a 32-byte shared
   secret.
3. The shared secret keys a `Channel` (12-byte counter nonce per frame,
   4-byte big-endian length prefix, 16-byte Poly1305 tag per frame).
4. `remote` sends an `AUTH_CHALLENGE` frame, then on an OK reply sends a
   `SPAWN_SHELL` request and pumps stdin/stdout through the channel with
   the local tty in raw mode.
5. `rcopy` sends a `COPY` request frame (`{op, name_len, name_bytes,
   size, sha256}`), then streams the source file in 4096-byte chunks,
   each acknowledged by the server.

## Known gaps at this landing

- **Entropy source.** No CSPRNG intrinsic (`SecureRandom::fill`) or
  `rdrand` mnemonic is available in the current paideia-as toolchain.
  `Kem::kem_fill_seed_bytes` derives KEM seed material from `rdtsc` ticks
  mixed with a per-process counter -- **not cryptographically strong**.
  This is flagged prominently in `src/kem.pdx` and must be replaced once
  a real linked entropy primitive exists.
- **File integrity hash.** No `Sha256` stdlib trait is linked yet
  (`crates/paideia-as-stdlib/pdx/crypto/` has `argon2id`,
  `chacha20_poly1305`, and `ml_kem_768` only). `Rcopy::rc_sha256_stub`
  fills the `sha256` field of the `COPY` request with 32 zero bytes and
  is clearly marked as a stub pending a real digest primitive.
- **tty raw mode.** `KIND_TTY` is not yet in the kernel's
  `KIND_SEEDABLE_TABLE` for non-shell processes (see
  `tools/user/shell/src/line_reader.pdx`). `remote`'s raw-mode call
  sites are real `cap_invoke`s but fail closed until that loader-side
  gap closes; the pump loop still runs (over cooked-mode tty I/O) if
  raw mode cannot be entered.
- **Hostname resolution.** No DNS/resolver syscall exists; `<host>` must
  be a dotted-quad IPv4 literal (`a.b.c.d`), matching every other
  networked user tool in this ecosystem (`pdxsock`).

## Connection-success fingerprint (`remote#6`)

On a successful `Kem::kem_client_handshake`, `remote` writes
`remote ok host=<H> peer_key=<hex8>\n` to fd 2. Two design notes:

- **"peer's public key" reading.** This protocol's client never
  receives a public key back from the server (only a ciphertext it
  decapsulates locally -- see `src/kem.pdx`'s module header). The only
  ML-KEM public key material that exists client-side is `kem_ek`, the
  encapsulation key this client generated and sent to the peer;
  `peer_key` hashes that. A real server-side peer would see the same
  `ek` bytes cross the wire, so this is the closest available reading
  of "peer's public key" given this round's client-only scope.
- **No hash primitive is linked.** `kem_peer_key_hash64` is Jenkins'
  one-at-a-time hash (public-domain, non-cryptographic) run natively
  in a 64-bit register (`add`/`xor`/`shl`/`shr` only -- no `imul`, no
  `and reg, imm64` truncation risk). This is a greppable log
  fingerprint, not a security property.

See `CHANGELOG.md` for the per-issue landing history.
