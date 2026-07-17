#!/usr/bin/env bash

# Crea la versione App Store, associa la build già elaborata e la invia ad Apple.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR
readonly API_CONFIG_PATH="${APP_STORE_CONNECT_CONFIG_PATH:-$ROOT_DIR/.env.appstore}"

if [[ -f "$API_CONFIG_PATH" ]]; then
  # El file local resta ignorà da Git e passa i valori anca a Fastlane.
  set -a
  # shellcheck source=/dev/null
  source "$API_CONFIG_PATH"
  set +a
fi

check_only=false
case "${1:-}" in
  "") ;;
  --check) check_only=true ;;
  *)
    echo "Uso: $0 [--check]" >&2
    exit 1
    ;;
esac

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "La pubblicazione App Store va eseguita su macOS." >&2
  exit 1
fi

if ! command -v fastlane >/dev/null 2>&1; then
  echo "Comando richiesto non trovato: fastlane" >&2
  exit 1
fi

version_value="$(sed -nE 's/^version:[[:space:]]*([^[:space:]]+).*/\1/p' "$ROOT_DIR/pubspec.yaml" | head -n 1)"
if [[ ! "$version_value" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$ ]]; then
  echo "Versione non valida in pubspec.yaml: ${version_value:-mancante}" >&2
  exit 1
fi

readonly marketing_version="${BASH_REMATCH[1]}"
readonly build_number="${BASH_REMATCH[2]}"
readonly metadata_locales=(it en-US fr-FR de-DE)
readonly api_key_id="${APP_STORE_CONNECT_KEY_ID:-}"
readonly api_issuer_id="${APP_STORE_CONNECT_ISSUER_ID:-}"
readonly api_key_path="${APP_STORE_CONNECT_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${api_key_id}.p8}"

for locale in "${metadata_locales[@]}"; do
  release_notes="$ROOT_DIR/app_store/metadata/$locale/release_notes.txt"
  if [[ ! -s "$release_notes" ]]; then
    echo "Note di rilascio mancanti o vuote: $release_notes" >&2
    exit 1
  fi
done

if [[ -z "$api_key_id" || -z "$api_issuer_id" ]]; then
  echo "Configura APP_STORE_CONNECT_KEY_ID e APP_STORE_CONNECT_ISSUER_ID in $API_CONFIG_PATH." >&2
  exit 1
fi

if [[ ! -f "$api_key_path" ]]; then
  echo "Chiave App Store Connect non trovata: $api_key_path" >&2
  exit 1
fi

api_key_mode="$(stat -f '%Lp' "$api_key_path")"
if (( (8#$api_key_mode & 077) != 0 )); then
  echo "Permessi troppo aperti sulla chiave App Store Connect: $api_key_mode (richiesto 600 o più restrittivo)." >&2
  exit 1
fi

if [[ "$check_only" == true ]]; then
  echo "Configurazione pubblicazione App Store pronta per $marketing_version ($build_number)."
  exit 0
fi

cd "$ROOT_DIR"

# Fastlane el fa version, build, metadati e review in un colpo solo.
FASTLANE_SKIP_UPDATE_CHECK=1 fastlane ios submit_app_store \
  version:"$marketing_version" \
  build_number:"$build_number"
