#!/usr/bin/env bash
# Per-repo build script. Mirrors tools/user/pdxsock/tools/build.sh in
# the paideia-os monorepo (satellite-tool /bin seeding pipeline). Runs
# paideia-as build over every .pdx source, then links TWO flat ELF
# binaries via `ld -T link.ld`:
#
#   remote  <- src/remote_client.o + src/kem.o + src/channel.o
#   rcopy   <- src/rcopy.o         + src/kem.o + src/channel.o
#
# kem.pdx and channel.pdx are shared library modules (no `_start` of
# their own); remote_client.pdx and rcopy.pdx each define their own
# `_start`, so each link step sees exactly one entry symbol.
#
# Resolves paideia-as via (in order):
#   1. $PAIDEIA_AS env var
#   2. paideia-os checkout sibling to this repo:
#      ../paideia-os/tools/paideia-as/target/release/paideia-as
#   3. $HOME/Development/PaideiaOS/tools/paideia-as/target/release/paideia-as
#   4. paideia-as on $PATH (must be >= 0.36.0)
#
# Requires paideia-as >= 0.36.0 (mov_b/mov_d narrow-load mnemonics +
# @align attribute on .bss slots, exercised throughout src/*.pdx here).

set -euo pipefail
cd "$(dirname "$0")/.."

MIN_VERSION="0.36.0"

resolve_paideia_as() {
    if [ -n "${PAIDEIA_AS:-}" ] && [ -x "$PAIDEIA_AS" ]; then
        echo "$PAIDEIA_AS"; return
    fi
    for cand in \
        "../paideia-os/tools/paideia-as/target/release/paideia-as" \
        "$HOME/Development/PaideiaOS/tools/paideia-as/target/release/paideia-as"
    do
        if [ -x "$cand" ]; then
            echo "$cand"; return
        fi
    done
    if command -v paideia-as >/dev/null 2>&1; then
        command -v paideia-as; return
    fi
    return 1
}

version_ge() {
    # $1 = have, $2 = want ; returns 0 if have >= want
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

PA="$(resolve_paideia_as || true)"
if [ -z "$PA" ]; then
    echo "[build] FAIL: paideia-as not found. Set PAIDEIA_AS or clone paideia-os as a sibling." >&2
    exit 2
fi
VER="$("$PA" --version | awk '{print $2}')"
if ! version_ge "$VER" "$MIN_VERSION"; then
    echo "[build] FAIL: paideia-as $VER is too old, need >= $MIN_VERSION (found $PA)" >&2
    exit 2
fi
echo "[build] paideia-as $VER at $PA"

BUILD_DIR="build-out"
mkdir -p "$BUILD_DIR"

FAIL=0
COUNT=0
for pdx in src/*.pdx; do
    [ -f "$pdx" ] || continue
    COUNT=$((COUNT + 1))
    obj="$BUILD_DIR/$(basename "$pdx" .pdx).o"
    if ! "$PA" build --emit elf64 "$pdx" -o "$obj" 2>&1; then
        FAIL=$((FAIL + 1))
    fi
done

echo "[build] $COUNT source(s), $FAIL failure(s)"
[ "$FAIL" -eq 0 ] || exit 1
echo "[build] OK"

KEM_OBJ="$BUILD_DIR/kem.o"
CHANNEL_OBJ="$BUILD_DIR/channel.o"

link_bin() {
    local name="$1"
    local entry_obj="$2"
    echo "[link] ld -T link.ld -> $BUILD_DIR/$name.elf"
    ld -nostdlib --warn-common --fatal-warnings --gc-sections \
        -T link.ld \
        -o "$BUILD_DIR/$name.elf" \
        "$entry_obj" "$KEM_OBJ" "$CHANNEL_OBJ"
    echo "[link] OK -> $BUILD_DIR/$name.elf"

    objcopy -O binary "$BUILD_DIR/$name.elf" "$BUILD_DIR/$name.bin"
    echo "[link] OK -> $BUILD_DIR/$name.bin"
}

link_bin "remote" "$BUILD_DIR/remote_client.o"
link_bin "rcopy"  "$BUILD_DIR/rcopy.o"
