#!/usr/bin/env bash

# Costruisse, firma e carica TestFlight senza Apple ID, password o codici 2FA.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR
readonly EXPORT_OPTIONS="$ROOT_DIR/ios/ExportOptions-AppStore.plist"
readonly PROFILE_NAME="Rubrica Associati App Store"
readonly API_CONFIG_PATH="${APP_STORE_CONNECT_CONFIG_PATH:-$ROOT_DIR/.env.appstore}"

if [[ -f "$API_CONFIG_PATH" ]]; then
  # El file local resta ignorà da Git e passa i valori anca a Fastlane.
  set -a
  # shellcheck source=/dev/null
  source "$API_CONFIG_PATH"
  set +a
fi

readonly API_KEY_ID="${APP_STORE_CONNECT_KEY_ID:-}"
readonly API_ISSUER_ID="${APP_STORE_CONNECT_ISSUER_ID:-}"
readonly API_KEY_PATH="${APP_STORE_CONNECT_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${API_KEY_ID}.p8}"

flutter_bin="${FLUTTER_BIN:-$(command -v flutter || true)}"
if [[ -z "$flutter_bin" && -x /opt/flutter/bin/flutter ]]; then
  flutter_bin=/opt/flutter/bin/flutter
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "La release iOS va eseguita su macOS." >&2
  exit 1
fi

for command in plutil xcrun security; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Comando richiesto non trovato: $command" >&2
    exit 1
  fi
done

if [[ -z "$flutter_bin" ]]; then
  echo "Comando richiesto non trovato: flutter" >&2
  exit 1
fi

if [[ -z "$API_KEY_ID" || -z "$API_ISSUER_ID" ]]; then
  echo "Configura APP_STORE_CONNECT_KEY_ID e APP_STORE_CONNECT_ISSUER_ID in $API_CONFIG_PATH." >&2
  exit 1
fi

if [[ ! -f "$API_KEY_PATH" ]]; then
  echo "Chiave App Store Connect non trovata: $API_KEY_PATH" >&2
  exit 1
fi

api_key_mode="$(stat -f '%Lp' "$API_KEY_PATH")"
if (( (8#$api_key_mode & 077) != 0 )); then
  echo "Permessi troppo aperti sulla chiave App Store Connect: $api_key_mode (richiesto 600 o più restrittivo)." >&2
  exit 1
fi

signing_identities="$(security find-identity -v -p codesigning)"
if [[ "$signing_identities" != *'Apple Distribution: MESKATECH DI MESCALCHIN MARCO (T4RJLVSR79)'* ]]; then
  echo "Certificato Apple Distribution non disponibile nel Portachiavi." >&2
  exit 1
fi

profile_found=false
while IFS= read -r -d '' profile_path; do
  installed_profile_name="$(security cms -D -i "$profile_path" 2>/dev/null |
    plutil -extract Name raw -o - - 2>/dev/null || true)"
  if [[ "$installed_profile_name" == "$PROFILE_NAME" ]]; then
    profile_found=true
    break
  fi
done < <(find "$HOME/Library/MobileDevice/Provisioning Profiles" -name '*.mobileprovision' -type f -print0 2>/dev/null)

if [[ "$profile_found" != true ]]; then
  echo "Profilo di provisioning non installato: $PROFILE_NAME" >&2
  exit 1
fi

if [[ "${1:-}" == "--check" ]]; then
  echo "Configurazione TestFlight pronta."
  exit 0
fi

if [[ $# -gt 0 ]]; then
  echo "Uso: $0 [--check]" >&2
  exit 1
fi

cd "$ROOT_DIR"

# El numero build vien da pubspec.yaml: prima de rilassar, va sempre aumentà.
"$flutter_bin" build ipa --release --export-options-plist="$EXPORT_OPTIONS"

ipa_path="$(find build/ios/ipa -maxdepth 1 -name '*.ipa' -type f -print -quit)"
if [[ -z "$ipa_path" ]]; then
  echo "IPA non generata." >&2
  exit 1
fi

# Altool usa la chiave .p8 e no domanda gnente a Apple ID.
xcrun altool \
  --upload-app \
  --type ios \
  --file "$ipa_path" \
  --apiKey "$API_KEY_ID" \
  --apiIssuer "$API_ISSUER_ID"

echo "Upload TestFlight completato: $ipa_path"
