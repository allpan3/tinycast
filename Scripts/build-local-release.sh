#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if [[ $# != 2 || ! $1 =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ || ! $2 =~ ^[1-9][0-9]*$ ]]; then
    echo "Usage: ./Scripts/build-local-release.sh <upstream-stable-tag> <local-revision>" >&2
    exit 1
fi

UPSTREAM_TAG="$1"
REVISION="$2"
VERSION="${UPSTREAM_TAG#v}.${REVISION}"
RELEASE_TAG="local/v${VERSION}"
IDENTITY="Tinycast Self-Signed"
DERIVED="build/LocalReleaseDerivedData"
PACKAGES="build/HostPackages"
DMG="$PACKAGES/Tinycast-${VERSION}-arm64.dmg"
ZIP="$PACKAGES/Tinycast-${VERSION}-arm64.zip"
MANIFEST="$PACKAGES/Tinycast-${VERSION}-arm64.json"
BUILD_LOG="build/local-release-${VERSION}.log"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Commit the release changes before packaging." >&2
    exit 1
fi
UPSTREAM_COMMIT="$(git rev-parse "${UPSTREAM_TAG}^{commit}")"
if ! git merge-base --is-ancestor "$UPSTREAM_COMMIT" HEAD; then
    echo "Rebase the local changes onto ${UPSTREAM_TAG} first (docs/local-releases.md)." >&2
    exit 1
fi
while IFS= read -r tag; do
    if [[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        if [[ $tag != "$UPSTREAM_TAG" ]]; then
            echo "The checkout already includes newer upstream ${tag}; use that base." >&2
            exit 1
        fi
        break
    fi
done < <(git tag --merged HEAD --sort=-version:refname --list 'v[0-9]*')
if git rev-parse -q --verify "refs/tags/${RELEASE_TAG}" >/dev/null; then
    echo "${RELEASE_TAG} already exists; increment the local revision." >&2
    exit 1
fi
while IFS= read -r tag; do
    if [[ $tag =~ ^local/v${UPSTREAM_TAG#v}\.[1-9][0-9]*$ ]]; then
        if ! python3 -c 'import sys; sys.exit(int(sys.argv[1]) <= int(sys.argv[2]))' "$REVISION" "${tag##*.}"; then
            echo "Use a revision greater than ${tag##*.} for ${UPSTREAM_TAG}." >&2
            exit 1
        fi
        break
    fi
done < <(git tag --sort=-version:refname --list "local/v${UPSTREAM_TAG#v}.*")
if [[ -e $DMG || -e $ZIP || -e $MANIFEST ]]; then
    echo "Artifacts for ${VERSION} already exist; inspect them before retrying." >&2
    exit 1
fi
if ! security find-identity -p codesigning | grep -q "$IDENTITY"; then
    echo "Create the stable signing identity first (docs/signing.md)." >&2
    exit 1
fi

mkdir -p "$PACKAGES"
echo "Building Tinycast ${VERSION} from ${UPSTREAM_TAG}…"
if ! xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED" \
    ARCHS=arm64 PRODUCT_NAME=Tinycast TINYCAST_BUNDLE_IDENTIFIER=com.tinycast.app \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$REVISION" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" \
    OTHER_CODE_SIGN_FLAGS='--timestamp=none' build > "$BUILD_LOG" 2>&1; then
    tail -n 60 "$BUILD_LOG" >&2
    exit 1
fi

APP="$DERIVED/Build/Products/Release/Tinycast.app"
./Scripts/verify-signature.sh "$APP"
ACTUAL_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ $ACTUAL_VERSION == "$VERSION" ]]

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Tinycast.app"
ln -s /Applications "$STAGE/Applications"
diskutil image create from "$STAGE" --format UDZO --volumeName Tinycast "$DMG" >/dev/null
ditto -c -k --keepParent --sequesterRsrc "$APP" "$ZIP"
ditto -x -k "$ZIP" "$STAGE/zip-check"
./Scripts/verify-signature.sh "$STAGE/zip-check/Tinycast.app"

LOCAL_COMMIT="$(git rev-parse HEAD)"
python3 - "$MANIFEST" "$VERSION" "$UPSTREAM_TAG" "$UPSTREAM_COMMIT" "$LOCAL_COMMIT" "$DMG" "$ZIP" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

manifest, version, tag, upstream, commit, *files = sys.argv[1:]
data = {
    "version": version,
    "upstreamTag": tag,
    "upstreamCommit": upstream,
    "localCommit": commit,
    "bundleIdentifier": "com.tinycast.app",
    "architecture": "arm64",
    "sha256": {Path(file).name: hashlib.sha256(Path(file).read_bytes()).hexdigest() for file in files},
}
Path(manifest).write_text(json.dumps(data, indent=2) + "\n")
PY
git tag -a "$RELEASE_TAG" -m "Release Tinycast ${VERSION} based on ${UPSTREAM_TAG} (${UPSTREAM_COMMIT})"
echo "Packaged ${DMG} and ${ZIP}; provenance: ${MANIFEST}"
