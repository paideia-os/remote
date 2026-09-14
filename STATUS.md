# remote -- status

**Round:** R85 -- ssh/remote secure shell
**Current milestone:** Wave mu-05 audit + encaps parity (remote#8)
**Version:** 0.6.0 (folds the R85-closure M1-006/M1-007/M1-008 work,
previously landed without a version bump, plus this wave's audit
finding + `kem_encaps_raw` parity wrapper -- see CHANGELOG.md.)

## Wave mu-05 audit finding

A project-wide wave plan described `src/kem.pdx` as "currently WEAK
deterministic-key stub" needing real ML-KEM intrinsic calls. That was
stale: remote#2 (v0.5.0) already landed REAL kernel-linked
`MlKem768::keygen`/`::decaps` trait calls. This landing (remote#8)
corrects the record and adds `kem_encaps_raw` for trait-call parity;
see CHANGELOG.md `[0.6.0]` for the full finding.

See `design/roadmap/post-r60-daily-use-roadmap.md` §R85 (paideia-os
monorepo) for the full spec.

## Milestones

| Milestone | Scope | Status |
|---|---|---|
| M1-001 | Repo bootstrap (README/LICENSE/CHANGELOG/caps.decl/tools/build.sh/manifest.pdxsig) | **landed (remote#1, v0.5.0)** |
| M1-002 | `src/kem.pdx` -- ML-KEM-768 client handshake | **landed (remote#2, v0.5.0)** |
| M1-003 | `src/channel.pdx` -- ChaCha20-Poly1305 framed channel | **landed (remote#3, v0.5.0)** |
| M1-004 | `src/remote_client.pdx` -- `remote <host>` binary | **landed (remote#4, v0.5.0)** |
| M1-005 | `src/rcopy.pdx` -- `rcopy <local> <host>:<remote>` binary | **landed (remote#5, v0.5.0)** |
| M1-006 | Fingerprint `remote ok host=<H> peer_key=<hex8>` on connection success | **landed (remote#6, this closure)** |
| M1-007 | paideia-os-side seed sub-issue (cross-repo) | **landed (paideia-os side, per cross-repo escalation discipline)** |
| M1-008 | Round closure retrospective + `r85-closed` tag | **landed (remote#7, this closure)** |

## M1-006 landing details (remote#6)

`src/kem.pdx` gains four small helpers (`kem_hex_nibble`,
`kem_hash_to_hex8`, `kem_peer_key_hash64`, `kem_peer_key_fingerprint_hex`)
and `src/remote_client.pdx`'s `_start` calls the last of these
immediately after `kem_client_handshake` succeeds, then assembles and
`sys_write`s (fd 2) the line:

```
remote ok host=<H> peer_key=<hex8>\n
```

**Design note on "peer's public key":** in this protocol shape the
client never receives a public key back from the server (only a
ciphertext it decapsulates locally) -- see `src/kem.pdx`'s module
header. The only ML-KEM public key material that exists client-side
is `kem_ek`, the encapsulation key this client generated and sent to
the peer; `peer_key` hashes that. Both ends of a real session observe
the same `ek` bytes on the wire, so this is the closest available
reading of the issue text given the client-only scope of this round.
Documented alongside the other known gaps in README.md.

**Design note on the hash itself:** no hash primitive is linked in
the paideia-as stdlib (crypto/ ships `argon2id`, `chacha20_poly1305`,
`ml_kem_768` only). `kem_peer_key_hash64` is Jenkins' one-at-a-time
hash (public-domain, non-cryptographic) run natively in a 64-bit
register -- every step is `add`/`xor`/`shl`/`shr`, so register
wraparound at 64 bits is the reduction; no `imul`, and no
`and reg, imm64` sign-extension pitfall (`kem_hash_to_hex8` masks
each nibble with the SMALL, sign-safe `and rax, 0xF` instead of a
would-be single `and rax, 0xFFFFFFFF`, which sign-extends to all-ones
and masks nothing). This is a greppable log fingerprint, not a
security boundary -- collisions are expected and harmless.

## Known gaps carried forward (unchanged by this closure)

See README.md "Known gaps at this landing": `rdtsc`-derived KEM seed
entropy (not cryptographically strong), `rcopy`'s zero-byte `sha256`
stub, `KIND_TTY` fail-closed raw mode, IPv4-literal-only host
addressing. None of these are in scope for R85; a future round tracks
them.
