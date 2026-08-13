#!/usr/bin/env bash
# Universal AArch64 build for ScourgeBringer.
# Debian Buster pins project-built ELF requirements below GLIBC_2.30; the
# current NextOS sysroot is mounted read-only for headers only.
set -euo pipefail

PORT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUTPUT=scourgebringer-nextos
BUILDER_IMAGE=playfetch-builder:buster
BUILDER_IMAGE_ID=sha256:036c7910ea53bc78cc213452afa92fa83d55de1c51ae54f315af58b5a41a45cf
export LC_ALL=C
export TZ=UTC
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-1785628800}

if [ "${SCOURGE_BUSTER_IN_CONTAINER:-0}" != "1" ]; then
  REPOSITORY_ROOT=$(git -C "$PORT_DIR" rev-parse --show-toplevel)
  FRAMEWORK_PIN=$PORT_DIR/FRAMEWORK-PIN.json
  FRAMEWORK_UPSTREAM=${SCOURGE_FRAMEWORK_UPSTREAM:-https://github.com/NextOs-Ports/nextos_ports_android.git}
  FRAMEWORK_GIT_ROOT=$REPOSITORY_ROOT
  FRAMEWORK_FETCH_ROOT=""
  FRAMEWORK_SNAPSHOT=""
  cleanup_framework_snapshot() {
    if [ -n "$FRAMEWORK_SNAPSHOT" ]; then
      case $FRAMEWORK_SNAPSHOT in
        "${TMPDIR:-/tmp}"/scourge-framework-*)
          find "$FRAMEWORK_SNAPSHOT" -mindepth 1 -delete 2>/dev/null || true
          rmdir "$FRAMEWORK_SNAPSHOT" 2>/dev/null || true
          ;;
      esac
    fi
    if [ -n "$FRAMEWORK_FETCH_ROOT" ]; then
      case $FRAMEWORK_FETCH_ROOT in
        "${TMPDIR:-/tmp}"/scourge-framework-fetch.*)
          find "$FRAMEWORK_FETCH_ROOT" -mindepth 1 -delete 2>/dev/null || true
          rmdir "$FRAMEWORK_FETCH_ROOT" 2>/dev/null || true
          ;;
      esac
    fi
  }
  trap cleanup_framework_snapshot EXIT INT TERM
  [ -f "$FRAMEWORK_PIN" ] ||
    { echo "framework pin is missing: $FRAMEWORK_PIN" >&2; exit 1; }
  FRAMEWORK_COMMIT=$(python3 -B -c \
    'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["source_commit"])' \
    "$FRAMEWORK_PIN")
  if ! git -C "$FRAMEWORK_GIT_ROOT" cat-file -e \
      "$FRAMEWORK_COMMIT^{commit}" 2>/dev/null; then
    # The original monorepo already has the immutable object. A standalone
    # clone fetches only that exact commit, then verifies the resulting object
    # id before any source reaches the offline builder.
    FRAMEWORK_FETCH_ROOT=$(mktemp -d \
      "${TMPDIR:-/tmp}/scourge-framework-fetch.XXXXXX")
    git -C "$FRAMEWORK_FETCH_ROOT" init -q
    git -C "$FRAMEWORK_FETCH_ROOT" fetch --quiet --depth 1 \
      "$FRAMEWORK_UPSTREAM" "$FRAMEWORK_COMMIT"
    [ "$(git -C "$FRAMEWORK_FETCH_ROOT" rev-parse FETCH_HEAD)" = \
      "$FRAMEWORK_COMMIT" ] || {
      echo "fetched framework commit differs from pin" >&2
      exit 1
    }
    FRAMEWORK_GIT_ROOT=$FRAMEWORK_FETCH_ROOT
  fi

  # Never compile the moving framework checkout. Release bytes come from the
  # immutable commit recorded by this port, even when another framework branch
  # is currently checked out in the shared repository.
  FRAMEWORK_SNAPSHOT=$(mktemp -d \
    "${TMPDIR:-/tmp}/scourge-framework-${FRAMEWORK_COMMIT}.XXXXXX")
  git -C "$FRAMEWORK_GIT_ROOT" archive "$FRAMEWORK_COMMIT" framework |
    tar -x -C "$FRAMEWORK_SNAPSHOT"
  FRAMEWORK_SOURCE=$FRAMEWORK_SNAPSHOT/framework
  python3 -B - "$FRAMEWORK_PIN" "$FRAMEWORK_SOURCE" <<'PY'
import json
import pathlib
import re
import sys

pin_path = pathlib.Path(sys.argv[1])
framework = pathlib.Path(sys.argv[2])
pin = json.loads(pin_path.read_text(encoding="utf-8"))
for component, expected in sorted(pin["components"].items()):
    version_path = framework / component / "VERSION"
    if component == "nxextract" and not version_path.is_file():
        runtime_path = pin_path.parent / "nxextract" / "nxextract.py"
        runtime_text = runtime_path.read_text(encoding="utf-8")
        match = re.search(r'^NXEXTRACT_VERSION = "([^"]+)"$', runtime_text, re.M)
        if not match:
            raise SystemExit("bundled NXExtract version is unavailable")
        actual = match.group(1)
        if actual != expected:
            raise SystemExit(
                f"framework pin mismatch: {component} expected={expected} actual={actual}"
            )
        continue
    if not version_path.is_file():
        raise SystemExit(f"pinned framework component is missing: {component}")
    actual = version_path.read_text(encoding="utf-8").strip()
    if actual != expected:
        raise SystemExit(
            f"framework pin mismatch: {component} expected={expected} actual={actual}"
        )
print(
    "framework snapshot verified: "
    f"commit={pin['source_commit']} components={len(pin['components'])}"
)
PY
  NEXTOS_ROOT=${NEXTOS_ROOT:-"$HOME/NextOS-Elite-Edition"}
  NEXTOS_TOOLCHAIN=$(
    find -H "$NEXTOS_ROOT" -maxdepth 2 -type d \
      -path '*/build.NextOS-Retro-Elite-Edition-Amlogic-old.aarch64-*/toolchain' \
      -print | sort -V | tail -1
  )
  [ -n "$NEXTOS_TOOLCHAIN" ] ||
    { echo "NextOS header sysroot not found below $NEXTOS_ROOT" >&2; exit 1; }
  NEXTOS_SYSROOT=$NEXTOS_TOOLCHAIN/aarch64-libreelec-linux-gnu/sysroot
  [ -d "$NEXTOS_SYSROOT" ] ||
    { echo "NextOS sysroot not found: $NEXTOS_SYSROOT" >&2; exit 1; }
  command -v docker >/dev/null 2>&1 ||
    { echo "docker is required for the low-glibc build" >&2; exit 1; }
  ACTUAL_IMAGE_ID=$(docker image inspect "$BUILDER_IMAGE" \
    --format '{{.Id}}' 2>/dev/null) ||
    { echo "pinned offline builder is missing: $BUILDER_IMAGE" >&2; exit 1; }
  [ "$ACTUAL_IMAGE_ID" = "$BUILDER_IMAGE_ID" ] || {
    echo "builder image changed: $ACTUAL_IMAGE_ID" >&2
    exit 1
  }

  docker run --rm --network none \
    -e SCOURGE_BUSTER_IN_CONTAINER=1 \
    -e SCOURGE_HOST_UID="$(id -u)" \
    -e SCOURGE_HOST_GID="$(id -g)" \
    -e LC_ALL=C -e TZ=UTC -e SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
    -v "$PORT_DIR":/repo \
    -v "$FRAMEWORK_SOURCE":/framework:ro \
    -v "$NEXTOS_SYSROOT":/nxsr:ro \
    "$BUILDER_IMAGE_ID" \
    bash /repo/build.sh
  exit $?
fi

for tool in aarch64-linux-gnu-gcc aarch64-linux-gnu-nm \
            aarch64-linux-gnu-readelf file; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "missing tool in pinned builder: $tool" >&2
    exit 1
  }
done

CC=aarch64-linux-gnu-gcc
NM=aarch64-linux-gnu-nm
READELF=aarch64-linux-gnu-readelf
FRAMEWORK_ROOT=${SCOURGE_FRAMEWORK_ROOT:-/framework}
cd /repo

OBJDIR=$(mktemp -d)
STUBDIR=$(mktemp -d)
cleanup() {
  find "$OBJDIR" "$STUBDIR" -mindepth 1 -delete 2>/dev/null || true
  rmdir "$OBJDIR" "$STUBDIR" 2>/dev/null || true
}
trap cleanup EXIT

COMMON_INCLUDES=(
  -I src
  -I "$FRAMEWORK_ROOT/nxloader/include"
  -I "$FRAMEWORK_ROOT/nxloader/src"
  -I "$FRAMEWORK_ROOT/nxcompat/include"
  -I "$FRAMEWORK_ROOT/nxcompat/src"
  -I "$FRAMEWORK_ROOT/nxgl/include"
  -I "$FRAMEWORK_ROOT/nxgl/src"
  -I "$FRAMEWORK_ROOT/nxinput/include"
  -I "$FRAMEWORK_ROOT/nxinput/src"
  -I "$FRAMEWORK_ROOT/nxaudio/include"
  -I "$FRAMEWORK_ROOT/nxandroid/include"
  -I "$FRAMEWORK_ROOT/nxandroid/src"
)

OBJS=()
compile_source() {
  group=$1
  source=$2
  object="$OBJDIR/${group}_$(basename "${source%.c}").o"
  "$CC" -D_GNU_SOURCE -DPORT_WINDOW_TITLE='"ScourgeBringer"' \
    -std=gnu11 "${COMMON_INCLUDES[@]}" \
    -idirafter /nxsr/usr/include \
    -idirafter /nxsr/usr/include/SDL2 \
    -O2 -fPIC -fno-omit-frame-pointer \
    -Wno-int-conversion -Wno-incompatible-pointer-types \
    -Wno-unused-parameter -Wno-unused-function \
    -c "$source" -o "$object"
  OBJS+=("$object")
}

PORT_SOURCES=(
  src/main.c
  src/so_util.c
  src/jni_shim.c
  src/language_policy.c
  src/save_migration.c
  src/title_menu_guard.c
  src/imports.gen.c
  src/bionic_shims.c
  src/pthread_bridge.c
  src/sdv_egl_bridge.c
  src/aspect_fill.c
  src/present_fbo.c
  src/mono_trace.c
  src/fmod_shim.c
  src/aaudio_shim.c
  src/astc_shim.c
  src/etc1.c
  src/util.c
  src/error.c
  src/nx_port_framework.c
)
for source in "${PORT_SOURCES[@]}"; do
  compile_source scourge "$source"
done

for source in \
  "$FRAMEWORK_ROOT"/nxloader/src/nxloader.c \
  "$FRAMEWORK_ROOT"/nxloader/src/nxloader_elf32.c \
  "$FRAMEWORK_ROOT"/nxloader/src/nxloader_elf64.c \
  "$FRAMEWORK_ROOT"/nxloader/src/nxloader_hooks.c \
  "$FRAMEWORK_ROOT"/nxloader/src/nxloader_protect.c \
  "$FRAMEWORK_ROOT"/nxloader/src/nxloader_registry.c; do
  compile_source nxloader "$source"
done

for source in "$FRAMEWORK_ROOT"/nxcompat/src/*.c; do
  compile_source nxcompat "$source"
done
for source in "$FRAMEWORK_ROOT"/nxgl/src/*.c; do
  compile_source nxgl "$source"
done
for source in "$FRAMEWORK_ROOT"/nxinput/src/*.c; do
  compile_source nxinput "$source"
done
compile_source nxaudio "$FRAMEWORK_ROOT/nxaudio/src/nxaudio.c"
compile_source nxandroid "$FRAMEWORK_ROOT/nxandroid/src/nxandroid.c"
compile_source nxandroid "$FRAMEWORK_ROOT/nxandroid/src/nxandroid_imports.c"

UNDEFINED=$("$NM" --undefined-only "${OBJS[@]}" 2>/dev/null |
  awk '{print $NF}' | sort -u)

stub_lib() {
  stub_name=$1
  stub_soname=$2
  stub_regex=$3
  : > "$STUBDIR/$stub_name.c"
  for symbol in $(printf '%s\n' "$UNDEFINED" | grep -E "$stub_regex" || true); do
    printf 'void %s(void) {}\n' "$symbol" >> "$STUBDIR/$stub_name.c"
  done
  "$CC" -shared -fPIC -nostdlib -Wl,-soname,"$stub_soname" \
    "$STUBDIR/$stub_name.c" -o "$STUBDIR/lib$stub_name.so"
}

stub_lib SDL2 libSDL2-2.0.so.0 '^SDL_'
stub_lib EGL libEGL.so.1 '^egl[A-Z]'
stub_lib GLESv2 libGLESv2.so.2 '^gl[A-Z]'
stub_lib z libz.so.1 \
  '^(adler32|compress|compress2|compressBound|crc32|deflate|inflate|uncompress|zlibVersion)'

"$CC" -fPIE -pie -rdynamic -o "$OUTPUT" "${OBJS[@]}" \
  -L"$STUBDIR" -lSDL2 -lEGL -lGLESv2 -lz \
  -ldl -lm -lpthread -lgcc_s

MAX_GLIBC=$(
  "$READELF" --version-info "$OUTPUT" |
    grep -oE 'GLIBC_[0-9]+([.][0-9]+)*' |
    sort -Vu | tail -1
)
[ -n "$MAX_GLIBC" ] ||
  { echo "unable to determine GLIBC requirement" >&2; exit 1; }
version_number=${MAX_GLIBC#GLIBC_}
major=${version_number%%.*}
rest=${version_number#*.}
minor=${rest%%.*}
if [ "$major" -gt 2 ] ||
   { [ "$major" -eq 2 ] && [ "$minor" -gt 30 ]; }; then
  echo "FAIL: $OUTPUT requires $MAX_GLIBC (limit GLIBC_2.30)" >&2
  exit 1
fi

NEEDED=$("$READELF" -dW "$OUTPUT" | awk -F'[][]' '/NEEDED/ {print $2}' | sort)
while IFS= read -r needed; do
  case "$needed" in
    libSDL2-2.0.so.0|libEGL.so.1|libGLESv2.so.2|libz.so.1|\
    libdl.so.2|libm.so.6|libpthread.so.0|libgcc_s.so.1|libc.so.6|librt.so.1)
      ;;
    *)
      echo "FAIL: unexpected DT_NEEDED: $needed" >&2
      exit 1
      ;;
  esac
done <<< "$NEEDED"

if [ -n "${SCOURGE_HOST_UID:-}" ] && [ -n "${SCOURGE_HOST_GID:-}" ]; then
  chown "$SCOURGE_HOST_UID:$SCOURGE_HOST_GID" "$OUTPUT" 2>/dev/null || true
fi

echo "UNIVERSAL AARCH64 BUILD OK -> $OUTPUT"
echo "max glibc: $MAX_GLIBC (limit GLIBC_2.30)"
echo "DT_NEEDED: $(echo "$NEEDED" | tr '\n' ' ')"
file "$OUTPUT"
sha256sum "$OUTPUT"
