# R85 Retrospective: ssh/remote secure shell

**Date:** 2026-09-13
**Milestones:** R85.M1-001 through R85.M1-008 (repo bootstrap through
round closure).
**Issues closed at landing:** remote#1, remote#2, remote#3, remote#4,
remote#5, remote#6, remote#7 (this landing covers remote#6 + remote#7;
remote#1..#5 landed in Wave SS as v0.5.0 -- see CHANGELOG.md `[0.5.0]`),
plus the paideia-os-side R85.M1-007 seed sub-issue (cross-repo dep).
**HEAD at closure:** `remote` (this repo), tag `r85-closed`.
**Release tag:** `r85-closed`.

## Round intent

R85 gives PaideiaOS remote administration without a physical console:
an `remote <host>` secure-shell-shaped client and an `rcopy <local>
<host>:<remote>` file-copy client, both post-quantum-secured via an
ML-KEM-768 (FIPS 203) key exchange feeding a ChaCha20-Poly1305 AEAD
framed transport. The round is explicitly client-only -- a future
`remoted` daemon (server side) is out of scope, tracked as a known gap
throughout.

## Per-milestone disposition

### M1-001..M1-005 -- initial landing -- LANDED (Wave SS, v0.5.0)

Repo bootstrap, `src/kem.pdx` (ML-KEM-768 client handshake),
`src/channel.pdx` (ChaCha20-Poly1305 framed channel), `src/
remote_client.pdx` (`remote` binary), `src/rcopy.pdx` (`rcopy`
binary). See CHANGELOG.md `[0.5.0]` for the full per-issue summary;
not repeated here.

### M1-006 -- fingerprint `remote ok host=<H> peer_key=<hex8>` -- LANDED (remote#6)

Added a connection-success fingerprint emitted to fd 2 immediately
after `Kem::kem_client_handshake` succeeds in `RemoteClient::_start`.

**Spec ambiguity resolved -- "peer's ML-KEM public key":** the M1-002
protocol has the client generate an ephemeral keypair and send its
public key (`ek`) to the server; the server never sends a public key
back (only a ciphertext the client decapsulates). So the client has
no "peer" public key to hash. Resolved by hashing `kem_ek` itself --
the one ML-KEM public key that exists in this process, and the same
bytes a real server-side peer would see cross the wire for this
session. Flagged as a design note in `src/kem.pdx`'s module header,
README.md, and STATUS.md rather than silently guessed at.

**Spec-adjacent gap -- no hash primitive is linked:** `crypto/` ships
`argon2id`, `chacha20_poly1305`, `ml_kem_768` only (the same gap
`Rcopy::rc_sha256_stub` already documents for the `sha256` field).
Rather than block on a stdlib addition, this landing implements
Jenkins' one-at-a-time hash (public-domain, non-cryptographic) as
four small `src/kem.pdx` functions (`kem_hex_nibble`,
`kem_hash_to_hex8`, `kem_peer_key_hash64`, `kem_peer_key_fingerprint_
hex`), using only `add`/`xor`/`shl`/`shr` so 64-bit register
wraparound performs the modular reduction with zero `imul` and zero
`and reg, imm64` risk (see the encoder-pitfalls note below). This is
adequate for a greppable log fingerprint; it is explicitly NOT a
security property, and the module header says so.

### M1-007 -- paideia-os-side seed sub-issue -- LANDED (cross-repo)

Tracked and closed on the paideia-os side per the cross-repo
escalation discipline; a dependency of M1-008, not touched by this
repo's own commit history.

### M1-008 -- round closure -- LANDED (remote#7, this commit)

This retrospective + STATUS.md + the `r85-closed` tag.

## What did NOT land in R85

- **No server side.** `remoted` (the daemon `remote`/`rcopy` talk to)
  does not exist in any repo yet. Every wire-protocol byte this round
  defines is written from the client's assumption of what a
  compliant server does; nothing here has been round-tripped against
  a real peer.
- **No CSPRNG-backed KEM seeding.** `Kem::kem_fill_seed_bytes` remains
  `rdtsc`-derived, flagged non-cryptographic in three places (module
  header, README.md, this retrospective).
- **No real file-integrity hash for `rcopy`.** `rc_sha256_stub` still
  zero-fills the 32-byte digest field.
- **No `KIND_TTY` non-shell seed.** Raw-mode `cap_invoke` calls are
  real but fail closed; the pump loop degrades to cooked-mode I/O.
- **No hostname resolution.** `<host>` must be a dotted-quad IPv4
  literal.

None of these are M1-006/M1-007/M1-008 scope; they carry forward as
known gaps for whichever future round adds the `remoted` daemon.

## Encoder pitfalls hit (for the next softarch touching this repo)

- **`and reg, imm64` sign-extension.** A single `and rax, 0xFFFFFFFF`
  to truncate a 64-bit value to its low 32 bits does NOT work: the
  assembler encodes `AND r/m64, imm32` which sign-extends the imm32
  operand to 64 bits first, so `0xFFFFFFFF` (top bit set) becomes
  `0xFFFFFFFFFFFFFFFF` and the "mask" is a no-op. Avoided here by (a)
  choosing a hash construction where 64-bit register wraparound IS
  the truncation (no masking needed at all), and (b) where an actual
  small mask was needed (`and rax, 0xF` for a hex nibble), using a
  SMALL positive immediate, which is safe.
- **No 2-op `imul`.** Every multiply-shaped step in this landing (the
  hash's `state << N` avalanche terms) is a plain `shl`/`add`/`xor`,
  matching the shl-3/add/add ×10 idiom already established in
  `rc_parse_ipv4`.

## Files touched

| File | Kind | Notes |
|---|---|---|
| `src/kem.pdx` | edit | +4 functions: `kem_hex_nibble`, `kem_hash_to_hex8`, `kem_peer_key_hash64`, `kem_peer_key_fingerprint_hex` (remote#6) |
| `src/remote_client.pdx` | edit | `_start` grows a 5th callee-save push (r15) + fingerprint assembly/emit block right after the KEM handshake succeeds (remote#6) |
| `STATUS.md` | new | this closure's milestone table |
| `design/round-retrospectives/r85-closure.md` | new (this file) | remote#7 |

## Cross-references

- `CHANGELOG.md` `[0.5.0]` -- the M1-001..M1-005 initial landing this
  closure builds on.
- `README.md` "Known gaps at this landing" -- carries the entropy /
  sha256-stub / tty / hostname gaps this closure does not touch, plus
  the new peer_key design note.
- paideia-os `design/roadmap/post-r60-daily-use-roadmap.md` §R85 --
  the round's originating spec.
