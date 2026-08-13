#!/usr/bin/env bash
# Materialize pinned shared inputs outside Git and bundle test.8 reproducibly.
set -euo pipefail

export LC_ALL=C
export TZ=UTC
export PYTHONDONTWRITEBYTECODE=1
umask 077

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PORT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)
REPOSITORY_ROOT=$(git -C "$PORT_DIR" rev-parse --show-toplevel)
FRAMEWORK_ROOT=${NEXTOS_FRAMEWORK_ROOT:-}
if [[ -z $FRAMEWORK_ROOT && -d $REPOSITORY_ROOT/framework ]]; then
  FRAMEWORK_ROOT=$REPOSITORY_ROOT/framework
fi
[[ -n $FRAMEWORK_ROOT && -d $FRAMEWORK_ROOT ]] || {
  printf '%s\n' \
    'set NEXTOS_FRAMEWORK_ROOT to the pinned external NextOS framework tree' >&2
  exit 1
}
FRAMEWORK_ROOT=$(CDPATH= cd -- "$FRAMEWORK_ROOT" && pwd -P)

NXEXTRACT_ROOT=${NXEXTRACT_SOURCE_ROOT:-}
if [[ -z $NXEXTRACT_ROOT &&
      -d $REPOSITORY_ROOT/suportando_outros_devices/extrator-universal ]]; then
  NXEXTRACT_ROOT=$REPOSITORY_ROOT/suportando_outros_devices/extrator-universal
fi
[[ -n $NXEXTRACT_ROOT && -d $NXEXTRACT_ROOT ]] || {
  printf '%s\n' \
    'set NXEXTRACT_SOURCE_ROOT to the pinned canonical NXExtract tree' >&2
  exit 1
}
NXEXTRACT_ROOT=$(CDPATH= cd -- "$NXEXTRACT_ROOT" && pwd -P)

NXGENERATOR=$FRAMEWORK_ROOT/nxbootstrap/tools/generate-port.py
NXBOOTSTRAP_TEMPLATE=$FRAMEWORK_ROOT/nxbootstrap/templates/launcher.sh.in
NXRELEASE=$FRAMEWORK_ROOT/nxrelease/nxrelease.py
NXEXTRACT_UI_SOURCE=$NXEXTRACT_ROOT/ui/build/nxextract-ui
MANIFEST=$PORT_DIR/nxrelease.json
DESTINATION=${1:-"$PORT_DIR/.build/release-1.0.0-test.8"}
ARCHIVE_NAME=scourgebringer-1.0.0-test.8.zip
WORK_ROOT=""
SOURCE_ROOT=""
BUNDLE_MANIFEST=""

fail() {
  printf 'scourgebringer package error: %s\n' "$*" >&2
  exit 1
}

require_pinned_file() {
  local input_path=$1 expected_sha256=$2 label=$3
  [[ -f $input_path && ! -L $input_path ]] ||
    fail "$label is missing or unsafe"
  [[ $(sha256sum -- "$input_path" | awk '{print $1}') == "$expected_sha256" ]] ||
    fail "$label SHA-256 drifted"
}

require_pinned_file \
  "$FRAMEWORK_ROOT/nxbootstrap/VERSION" \
  798a8d19f2adf20f8711b3c93b6b312369b11d7a7e7043fe533c13c268ac78be \
  'NXBootstrap VERSION'
[[ $(<"$FRAMEWORK_ROOT/nxbootstrap/VERSION") == 0.6.8 ]] ||
  fail 'NXBootstrap version drifted'
require_pinned_file \
  "$NXGENERATOR" \
  571cbc2e8dfcc60ae49a5ba2aa85db4e94a1938fbb683da4196117bb3d329850 \
  'NXBootstrap generator'
require_pinned_file \
  "$NXBOOTSTRAP_TEMPLATE" \
  c8aae3fabebaac14448d05c30645f8cf63801eb84d5449f7948931c1421b3e4b \
  'NXBootstrap launcher template'
require_pinned_file \
  "$FRAMEWORK_ROOT/nxrelease/VERSION" \
  be3c6d2c6c406a64d44f0b6464a887e290416dd90c524094485b1be00936d6d7 \
  'NXRelease VERSION'
[[ $(<"$FRAMEWORK_ROOT/nxrelease/VERSION") == 0.2.6 ]] ||
  fail 'NXRelease version drifted'
require_pinned_file \
  "$NXRELEASE" \
  f7ba3eda7d3d9e4318f5e8d83d16f05ea71b5d62c66961275df78a82cf6aa769 \
  'NXRelease tool'
require_pinned_file \
  "$NXEXTRACT_ROOT/VERSION" \
  5844ffcc346f89c07b13ba7596bfb3788ed73f4755e541182d7822d43b7c7a24 \
  'NXExtract VERSION'
[[ $(<"$NXEXTRACT_ROOT/VERSION") == 1.2.6 ]] ||
  fail 'NXExtract version drifted'
require_pinned_file \
  "$NXEXTRACT_ROOT/nxextract.py" \
  a4a8e5d3bf2a1344491e27921c54430ee9b4e3fedd0160631da96734fa3d5170 \
  'NXExtract runtime'
require_pinned_file \
  "$NXEXTRACT_ROOT/run-extractor.sh" \
  179b72f02b9dfdf3ed1bdc382d074fb4ef07f83e3d62cfccfc74a950e68679c2 \
  'NXExtract runner'
require_pinned_file \
  "$NXEXTRACT_ROOT/nxextract-runtime-env.sh" \
  332919a9960d4317563b647f9932d1a4367da147a425fe2f78eafd706f01563f \
  'NXExtract runtime environment'
require_pinned_file \
  "$NXEXTRACT_UI_SOURCE" \
  046afb583f5a211c946495e639409f81d9cfec706788eeccb7924b0e8e5a50b6 \
  'NXExtract UI'
require_pinned_file \
  "$NXEXTRACT_ROOT/LICENSE" \
  74d7d9d40e27fbfe23cb462f9608fa07cbe53ffb0b88a0da9e85dda240c2c788 \
  'NXExtract licence'
cmp -s "$NXEXTRACT_ROOT/LICENSE" "$PORT_DIR/licenses/NXExtract-MIT.txt" ||
  fail 'tracked NXExtract licence notice drifted'
require_pinned_file \
  "$MANIFEST" \
  7183fa8f4e0049da0000604ea72987ce2b8cd8f1813c1ad330ee50576f1a73a2 \
  'source release manifest'
[[ ! -e $DESTINATION && ! -L $DESTINATION ]] ||
  fail "destination already exists: $DESTINATION"

WORK_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/scourge-package.XXXXXX")
cleanup() {
  case $WORK_ROOT in
    "${TMPDIR:-/tmp}"/scourge-package.*)
      [[ -d $WORK_ROOT ]] && find "$WORK_ROOT" -mindepth 1 -delete
      [[ -d $WORK_ROOT ]] && rmdir "$WORK_ROOT"
      ;;
    '') ;;
    *) printf 'refusing unsafe temporary cleanup: %s\n' "$WORK_ROOT" >&2 ;;
  esac
}
trap cleanup EXIT INT TERM
SOURCE_ROOT=$WORK_ROOT/source
BUNDLE_MANIFEST=$SOURCE_ROOT/nxrelease.json
mkdir -p -- "$SOURCE_ROOT/nxextract"

# test.8 was originally sealed while the audited package README occupied the
# source path README.md. Recreate that exact input manifest only in the
# temporary source mirror so the published ZIP remains byte-for-byte stable.
python3 -B - "$MANIFEST" "$BUNDLE_MANIFEST" <<'PY'
import hashlib
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
needle = '"source": "package/README.md"'
if source.count(needle) != 1:
    raise SystemExit("package README mapping is missing or ambiguous")
sealed = source.replace(needle, '"source": "README.md"')
digest = hashlib.sha256(sealed.encode("utf-8")).hexdigest()
expected = "a6addd812d7dfd71b0b7e81cadc295ade8317908a53329e6d5175c2139ddc5e6"
if digest != expected:
    raise SystemExit(f"sealed manifest drifted: {digest}")
pathlib.Path(sys.argv[2]).write_text(sealed, encoding="utf-8")
PY

python3 -B "$NXGENERATOR" "$PORT_DIR/nxport.json" \
  --output "$WORK_ROOT/generated" >/dev/null
cmp -s "$PORT_DIR/nxport.json" \
  "$WORK_ROOT/generated/scourgebringer/nxport.json" ||
  fail 'generated nxport.json drifted'
install -m 0755 -- "$WORK_ROOT/generated/ScourgeBringer.sh" \
  "$SOURCE_ROOT/ScourgeBringer.sh"
require_pinned_file \
  "$SOURCE_ROOT/ScourgeBringer.sh" \
  4b58c23db5bacdc0628bc4e63f3aa89f90e132fb4dd80a6fb533576b4ec55776 \
  'generated launcher'

for runtime_file in nxextract.py run-extractor.sh nxextract-runtime-env.sh; do
  install -m 0644 -- "$NXEXTRACT_ROOT/$runtime_file" \
    "$SOURCE_ROOT/nxextract/$runtime_file"
done
install -m 0755 -- "$NXEXTRACT_UI_SOURCE" \
  "$SOURCE_ROOT/nxextract/nxextract-ui"
install -m 0644 -- "$PORT_DIR/package/make-assembly-apk.py" \
  "$SOURCE_ROOT/nxextract/make-assembly-apk.py"

if [[ ${SCOURGE_SKIP_BUILD:-0} != 1 ]]; then
  "$PORT_DIR/build.sh"
fi
require_pinned_file \
  "$PORT_DIR/scourgebringer-nextos" \
  a245edea4cf83dd9f1dc0e9b808ddf6e9d15ecaee35433bba8bc78c2555c0273 \
  'project executable'

python3 -B - "$BUNDLE_MANIFEST" "$PORT_DIR" "$SOURCE_ROOT" <<'PY'
import json
import pathlib
import shutil
import sys

manifest_path = pathlib.Path(sys.argv[1])
port_root = pathlib.Path(sys.argv[2])
source_root = pathlib.Path(sys.argv[3])
materialized = {
    "ScourgeBringer.sh",
    "nxextract/make-assembly-apk.py",
    "nxextract/nxextract-runtime-env.sh",
    "nxextract/nxextract-ui",
    "nxextract/nxextract.py",
    "nxextract/run-extractor.sh",
}
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
for entry in manifest["files"]:
    relative = entry["source"]
    if relative in materialized:
        continue
    origin = (
        port_root / "package/README.md"
        if relative == "README.md"
        else port_root / relative
    )
    if not origin.is_file() or origin.is_symlink():
        raise SystemExit(f"unsafe static release input: {origin}")
    destination = source_root / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(origin, destination)
PY

python3 -B "$SOURCE_ROOT/nxextract/nxextract.py" recipe-check \
  --recipe "$SOURCE_ROOT/extractor.json"

python3 -B "$NXRELEASE" validate \
  --manifest "$BUNDLE_MANIFEST" --max-glibc 2.30
mkdir -p -- "$(dirname -- "$DESTINATION")"
python3 -B "$NXRELEASE" bundle \
  --manifest "$BUNDLE_MANIFEST" --stage "$WORK_ROOT/stage" \
  --destination "$DESTINATION" --archive-name "$ARCHIVE_NAME" \
  --max-glibc 2.30
python3 -B "$NXRELEASE" verify \
  --archive "$DESTINATION/$ARCHIVE_NAME" \
  --sha256-file "$DESTINATION/$ARCHIVE_NAME.sha256" --max-glibc 2.30

python3 -B - "$DESTINATION/$ARCHIVE_NAME" "$PORT_DIR/INSTALLATION.md" <<'PY'
import re
import sys
import zipfile
from pathlib import PurePosixPath

archive_path, installation_path = sys.argv[1:]
private = (b"192" + b".168.", b"/home/" + b"felipe", b"claude-" + b"1000")
forbidden_suffixes = (".apk", ".aab", ".apkm", ".apks", ".xapk", ".obb",
                      ".sav", ".log", ".tombstone")
shell_word = re.compile(r"(?<![/A-Za-z0-9_.-])s[t]at(?=[\t );&|]|$)")
expected_installation = open(installation_path, "rb").read()
with zipfile.ZipFile(archive_path) as archive:
    members = {info.filename: info for info in archive.infolist()}
    wanted = "scourgebringer/INSTALLATION.md"
    if wanted not in members or archive.read(wanted) != expected_installation:
        raise SystemExit("INSTALLATION.md is absent or differs from the recipe")
    for name, info in members.items():
        path = PurePosixPath(name)
        if path.is_absolute() or ".." in path.parts:
            raise SystemExit(f"unsafe ZIP member: {name}")
        lower = name.lower()
        if lower.endswith(forbidden_suffixes):
            raise SystemExit(f"forbidden owner/runtime data in ZIP: {name}")
        if info.is_dir():
            continue
        data = archive.read(name)
        if any(marker in data for marker in private):
            raise SystemExit(f"private marker in ZIP: {name}")
        if lower.endswith(".sh"):
            for number, line in enumerate(data.decode("utf-8").splitlines(), 1):
                if not line.lstrip().startswith("#") and shell_word.search(line):
                    raise SystemExit(
                        "external s" + f"tat command in {name}:{number}"
                    )
print(f"unpacked public ZIP audit: PASS members={len(members)}")
PY

printf 'ScourgeBringer data-free test release: %s\n' \
  "$DESTINATION/$ARCHIVE_NAME"
sha256sum -- "$DESTINATION/$ARCHIVE_NAME"
