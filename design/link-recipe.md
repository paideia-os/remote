# remote / rcopy link recipe -- paideia-crypto runtime symbols

## Status

Pre-existing, undocumented until now. `tools/build.sh` links both
`remote` and `rcopy` binaries against `src/kem.o` and `src/channel.o`
only. Both of those objects call into the paideia-as stdlib crypto
surface (`crypto` effect, `paideia.crypto` capability):

- `src/channel.pdx` -- `ch_seal_raw` / `ch_open_raw` elaborate to
  `chacha20_poly1305` seal/open.
- `src/kem.pdx` -- elaborates to `ml_kem_768` keygen/encaps/decaps.

The elaborator's `stdlib_lowering::cryptoops` recipe (paideia-as repo,
`crates/paideia-as-stdlib/pdx/crypto/{chacha20_poly1305,ml_kem_768}.pdx`)
lowers these calls to **extern** references against the paideia-as
satellite crypto runtime, not to code compiled inline into `kem.o` /
`channel.o`. Concretely, the link step fails undefined-symbol on (at
least):

```
paideia_crypto_chacha20_poly1305_seal
paideia_crypto_chacha20_poly1305_open
paideia_crypto_ml_kem_768_keygen
paideia_crypto_ml_kem_768_encaps
paideia_crypto_ml_kem_768_decaps
```

## Where the symbols live

The paideia-as toolchain builds a static archive that defines these
entry points:

```
<paideia-os checkout>/tools/paideia-as/target/release/libpaideia_satellite_runtime.a
```

Confirmed present at landing time via:

```
nm libpaideia_satellite_runtime.a | grep paideia_crypto_
0000000000000000 T paideia_crypto_chacha20_poly1305_open
0000000000000000 T paideia_crypto_chacha20_poly1305_seal
...
```

## Recipe

Add the runtime archive to both `ld` invocations in
`tools/build.sh`'s `link_bin()`:

```sh
ld -nostdlib --warn-common --fatal-warnings --gc-sections \
    -T link.ld \
    -o "$BUILD_DIR/$name.elf" \
    "$entry_obj" "$KEM_OBJ" "$CHANNEL_OBJ" \
    --extra-archive /path/to/libpaideia_satellite_runtime.a
```

`/path/to/libpaideia_satellite_runtime.a` resolves the same way
`tools/build.sh` already resolves `paideia-as` itself (sibling
`../paideia-os` checkout, then `$HOME/Development/PaideiaOS`, then a
`PAIDEIA_AS`-adjacent override) -- this repo intentionally does not
hardcode an absolute path, since `remote`/`rcopy` are built standalone
outside the monorepo tree as well as inside it.

## Why this is not applied in `tools/build.sh` yet

This landing documents the failure and the fix (`tools/build.sh` +
this file) without wiring the archive resolution logic in, because:

1. The archive's on-disk location depends on which paideia-as
   toolchain build produced it (`debug` vs `release`, and which of the
   several `deps/libpaideia_satellite_runtime-<hash>.a` copies cargo
   produced is the canonical one for a given checkout) -- resolving
   that robustly needs the same multi-candidate search
   `resolve_paideia_as()` already does for the compiler binary itself,
   extended to also probe for the runtime archive next to it.
2. Landing an untested resolution-and-link change without a build
   verification pass (builds in this org are run by the invoking
   session, never by the agent authoring the change) risks landing a
   broken `tools/build.sh` that fails differently rather than not at
   all.

The follow-up is: extend `resolve_paideia_as()` (or add a sibling
`resolve_satellite_runtime()`) to locate
`libpaideia_satellite_runtime.a` next to the resolved `paideia-as`
binary, then thread that path into both `link_bin` invocations via
`--extra-archive`, gated so a `remote`/`rcopy` build with no crypto
calls (should this repo ever split a crypto-free variant) does not
regress if the archive is absent.
