#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

MODE="${1:-upload}"          # full | upload  (default: upload = hızlı)
PROFILE="${2:-preview}"      # EAS build profili (full modunda)
DIST_DIR="./dist"
TMP_JSON=".eas-latest.json"

require_env () {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "❌ Missing env: $name"
    exit 1
  fi
}

# Son bitmiş Android build'in ID ve Artifact URL'ini çek
resolve_latest_build_meta () {
  echo "🔎 Fetching latest finished Android build meta…"
  bunx eas-cli build:list \
    --status finished \
    --platform android \
    --limit 1 \
    --json \
    --non-interactive > "$TMP_JSON"

  if ! [ -s "$TMP_JSON" ]; then
    echo "❌ Empty build list JSON."
    exit 1
  fi

  BUILD_ID=$(bun -e "const fs=require('fs');const j=JSON.parse(fs.readFileSync('$TMP_JSON','utf8'));console.log(j?.[0]?.id||'')")
  ARTIFACT_URL=$(bun -e "const fs=require('fs');const j=JSON.parse(fs.readFileSync('$TMP_JSON','utf8'));const a=j?.[0]?.artifacts||{};console.log(a.buildUrl||a.applicationArchiveUrl||'')")

  if [ -z "${BUILD_ID:-}" ]; then
    echo "❌ No finished Android build id found."
    cat "$TMP_JSON" || true
    exit 1
  fi
  if [ -z "${ARTIFACT_URL:-}" ]; then
    echo "❌ No artifact URL found in latest build."
    cat "$TMP_JSON" || true
    exit 1
  fi

  echo "✓ Latest build id: $BUILD_ID"
  echo "↘️  Artifact URL resolved."
}

download_artifact_url () {
  local url="$1"
  mkdir -p "$DIST_DIR"
  local fname="${DIST_DIR}/android-${BUILD_ID}.apk"
  echo "⬇️  Downloading APK via curl…"
  curl -L "$url" -o "$fname"
  APK_PATH="$fname"
  echo "✓ APK downloaded to: $APK_PATH"
}

pick_apk_from_dist () {
  APK_PATH=$(ls -1t "$DIST_DIR"/*.apk 2>/dev/null | head -n1 || true)
  if [ -z "${APK_PATH:-}" ]; then
    echo "❌ No APK found under $DIST_DIR"
    exit 1
  fi
  echo "✓ APK ready at: $APK_PATH"
}

distribute_to_firebase () {
  require_env FIREBASE_ANDROID_APP_ID
  require_env FIREBASE_GROUPS
  require_env FIREBASE_PROJECT

  local apk="$1"
  echo "🚀 Distributing to Firebase App Distribution…"
  bunx firebase-tools appdistribution:distribute "$apk" \
    --app "$FIREBASE_ANDROID_APP_ID" \
    --groups "$FIREBASE_GROUPS" \
    --project "$FIREBASE_PROJECT" \
    --release-notes "pBasket Android upload ($(date +%Y-%m-%d\ %H:%M))"
  echo "🎉 Done. Check Firebase App Distribution dashboard."
}

case "${MODE}" in
  full)
    echo "▶️  Building Android ($PROFILE) on EAS…"
    bunx eas-cli build -p android --profile "$PROFILE" --non-interactive --wait
    echo "✓ EAS build completed."

    resolve_latest_build_meta
    download_artifact_url "$ARTIFACT_URL"
    distribute_to_firebase "$APK_PATH"
    ;;
  upload)
    GIVEN_APK="${3:-}"
    if [ -n "$GIVEN_APK" ]; then
      APK_PATH="$GIVEN_APK"
      [ -f "$APK_PATH" ] || { echo "❌ APK not found: $APK_PATH"; exit 1; }
      echo "✓ Using provided APK: $APK_PATH"
    else
      resolve_latest_build_meta
      download_artifact_url "$ARTIFACT_URL"
    fi
    distribute_to_firebase "$APK_PATH"
    ;;
  *)
    echo "Usage:"
    echo "  scripts/release-android.sh [full|upload] [profile] [apk_path_if_upload]"
    echo "Examples:"
    echo "  scripts/release-android.sh full preview"
    echo "  scripts/release-android.sh upload"
    echo "  scripts/release-android.sh upload ./dist/app.apk"
    exit 1
    ;;
esac
