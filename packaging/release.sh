#!/usr/bin/env bash
# Publish a new version: build the app with the stable signing identity, zip it, sign the zip with the
# Sparkle EdDSA key from the login keychain (account "sound-recorder"), write appcast.xml and upload both
# as a GitHub release. Installed apps read …/releases/latest/download/appcast.xml (SUFeedURL).
# Usage: packaging/release.sh [version]   (defaults to the VERSION file; release notes may come from $NOTES)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"
NOTES="${NOTES:-}"
REPO="BillyND/sound-recorder"
OUT="$ROOT/out"
SIGN="$ROOT/packaging/sparkle-tools/bin/sign_update"
ZIP="$OUT/SoundRecorder-$VERSION.zip"
die() { echo "release: $*" >&2; exit 1; }

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must look like 1.2.3, got \"$VERSION\""
[ "$VERSION" = "$(tr -d '[:space:]' < "$ROOT/VERSION")" ] || die "VERSION file says $(cat "$ROOT/VERSION"); set it to $VERSION and commit first"
[ -x "$SIGN" ] || die "missing Sparkle tools: run make sparkle-tools"
[ -z "$(git -C "$ROOT" status --porcelain)" ] || die "uncommitted changes; commit them first"
git -C "$ROOT" fetch -q origin
git -C "$ROOT" merge-base --is-ancestor HEAD origin/main || die "HEAD is not on origin/main; push it first"

if gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1 || git -C "$ROOT" rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
  die "v$VERSION is already released; bump VERSION"
fi
LATEST="$(gh release list --repo "$REPO" --exclude-drafts --limit 100 --json tagName -q '.[].tagName' | sed 's/^v//' | sort -V | tail -1)"
if [ -n "$LATEST" ] && [ "$(printf '%s\n%s\n' "$LATEST" "$VERSION" | sort -V | tail -1)" != "$VERSION" ]; then
  die "v$VERSION is not newer than the published v$LATEST"
fi
if [ -z "$NOTES" ]; then # default notes: commit subjects since the previous release tag
  PREV="$(git -C "$ROOT" describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
  NOTES="$(git -C "$ROOT" log --format='- %s' ${PREV:+$PREV..}HEAD | head -30)"
fi

REQUIRE_IDENTITY=1 make -C "$ROOT" app VERSION="$VERSION" >/dev/null
APP="$OUT/Sound Recorder.app"
[ "$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")" = "$VERSION" ] || die "built app has the wrong version"
codesign --verify --deep --strict "$APP"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
SIG_ATTRS="$("$SIGN" --account sound-recorder "$ZIP")"   # sparkle:edSignature="…" length="…"
URL="https://github.com/$REPO/releases/download/v$VERSION/$(basename "$ZIP")"
NOTES_HTML="$(printf '%s\n' "$NOTES" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/^- \(.*\)$/<li>\1<\/li>/')"
cat > "$OUT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Sound Recorder</title>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <description><![CDATA[<ul>$NOTES_HTML</ul>]]></description>
      <enclosure url="$URL" type="application/octet-stream" $SIG_ATTRS/>
    </item>
  </channel>
</rss>
XML
gh release create "v$VERSION" "$ZIP" "$OUT/appcast.xml" --repo "$REPO" --target "$(git -C "$ROOT" rev-parse HEAD)" \
  --title "Sound Recorder $VERSION" --notes "$NOTES"
git -C "$ROOT" fetch -q --tags origin
echo "released v$VERSION: $URL"
