#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

MODE="${1:-upload}"          # full | upload  (default: upload = hızlı)
PROFILE="${2:-preview}"      # EAS build profili (full modunda)
DIST_DIR="./dist"
TMP_JSON=".eas-ios-latest.json"

require_env () {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "❌ Missing env: $name"
    exit 1
  fi
}

# .env.local varsa yükle
[ -f .env.local ] && source .env.local

require_env FIREBASE_IOS_APP_ID
require_env FIREBASE_PROJECT
require_env FIREBASE_GROUPS

resolve_latest_ios_meta () {
  echo "🔎 Fetching latest finished iOS build meta…"
  bunx eas-cli build:list \
    --status finished \
    --platform ios \
    --limit 1 \
    --json \
    --non-interactive > "$TMP_JSON"

  if ! [ -s "$TMP_JSON" ]; then
    echo "❌ Empty iOS build list JSON."
    exit 1
  fi

  BUILD_ID=$(bun -e "const fs=require('fs');const j=JSON.parse(fs.readFileSync('$TMP_JSON','utf8'));console.log(j?.[0]?.id||'')")
  ARTIFACT_URL=$(bun -e "const fs=require('fs');const j=JSON.parse(fs.readFileSync('$TMP_JSON','utf8'));const a=j?.[0]?.artifacts||{};console.log(a.buildUrl||a.applicationArchiveUrl||'')")

  if [ -z "${BUILD_ID:-}" ]; then
    echo '❌ No finished iOS build id found.'; cat "$TMP_JSON" || true; exit 1
  fi
  if [ -z "${ARTIFACT_URL:-}" ]; then
    echo '❌ No artifact URL found in latest iOS build.'; cat "$TMP_JSON" || true; exit 1
  fi

  echo "✓ Latest iOS build id: $BUILD_ID"
  echo "↘️  Artifact URL resolved."
}

download_ipa () {
  local url="$1"
  mkdir -p "$DIST_DIR"
  IPA_PATH="${DIST_DIR}/ios-${BUILD_ID}.ipa"
  echo "⬇️  Downloading IPA via curl…"
  curl --fail --location --retry 3 "$url" -o "$IPA_PATH"

  # Boyut ve tip kontrol
  if [ ! -s "$IPA_PATH" ]; then
    echo "❌ Downloaded IPA is empty."; exit 1
  fi
  echo "✓ IPA downloaded: $IPA_PATH ($(du -h "$IPA_PATH" | awk '{print $1'}))"
}

pick_ipa_from_dist () {
  IPA_PATH=$(ls -1t "$DIST_DIR"/*.ipa 2>/dev/null | head -n1 || true)
  if [ -z "${IPA_PATH:-}" ]; then
    echo "❌ No IPA found under $DIST_DIR"; exit 1
  fi
  echo "✓ IPA ready at: $IPA_PATH"
}

upload_to_firebase () {
  local ipa="$1"
  echo "📤 Uploading to Firebase App Distribution…"
  bunx firebase-tools appdistribution:distribute "$ipa" \
    --app "$FIREBASE_IOS_APP_ID" \
    --groups "$FIREBASE_GROUPS" \
    --project "$FIREBASE_PROJECT" \
    --release-notes "iOS Ad-Hoc upload ($(date +%Y-%m-%d\ %H:%M))" \
    --debug
  echo "✅ iOS dağıtımı tamamlandı!"
}

case "$MODE" in
  full)
    echo "🚀 iOS Ad-Hoc build başlatılıyor (profile: $PROFILE)…"
    bunx eas-cli build -p ios --profile "$PROFILE" --non-interactive --wait
    echo "✓ EAS iOS build completed."

    resolve_latest_ios_meta
    download_ipa "$ARTIFACT_URL"
    upload_to_firebase "$IPA_PATH"
    ;;
  upload)
    GIVEN_IPA="${3:-}"
    if [ -n "$GIVEN_IPA" ]; then
      IPA_PATH="$GIVEN_IPA"
      [ -f "$IPA_PATH" ] || { echo "❌ IPA not found: $IPA_PATH"; exit 1; }
      echo "✓ Using provided IPA: $IPA_PATH"
    else
      resolve_latest_ios_meta
      download_ipa "$ARTIFACT_URL"
    fi
    upload_to_firebase "$IPA_PATH"
    ;;
  *)
    echo "Usage:"
    echo "  scripts/release-ios.sh [full|upload] [profile] [ipa_path_if_upload]"
    echo "Examples:"
    echo "  scripts/release-ios.sh full preview"
    echo "  scripts/release-ios.sh upload"
    echo "  scripts/release-ios.sh upload ./dist/app.ipa"
    exit 1
    ;;
esac
