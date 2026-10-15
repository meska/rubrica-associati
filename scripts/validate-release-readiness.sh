#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repo_root
readonly supported_languages=(de en fr it)
readonly app_store_locales=(de-DE en-US fr-FR it)
readonly play_store_locales=(de-DE en-US fr-FR it-IT)
readonly microsoft_store_locales=(de-DE en-US fr-FR it-IT)
readonly mobile_screenshot_locales=(de-DE en-US fr-FR it-IT)
readonly mobile_screenshot_pages=(home detail form)
readonly tip_locales=(de-DE en-US fr-FR it-IT)
readonly expected_product_ids=(
  rubrica_tip_small
  rubrica_tip_medium
  rubrica_tip_large
  rubrica_tip_legendary
)

fail() {
  echo "Repository metadata: $*" >&2
  exit 1
}

require_nonempty() {
  local path="$1"
  [[ -s "$path" ]] || fail "file mancante o vuoto: ${path#"$repo_root"/}"
}

character_count() {
  local value="$1"
  printf '%s' "$value" | wc -m | tr -d ' '
}

validate_file_length() {
  local path="$1"
  local maximum="$2"
  local content
  local length
  content="$(<"$path")"
  length="$(character_count "$content")"
  [[ "$length" -le "$maximum" ]] ||
    fail "${path#"$repo_root"/} supera $maximum caratteri ($length)"
}

validate_https_url() {
  local path="$1"
  local value
  value="$(<"$path")"
  [[ "$value" =~ ^https://[^[:space:]]+$ ]] ||
    fail "URL HTTPS non valido in ${path#"$repo_root"/}"
}

validate_png_dimensions() {
  local path="$1"
  local width="$2"
  local height="$3"
  local file_description
  require_nonempty "$path"
  file_description="$(file -b "$path")"
  [[ "$file_description" == *"PNG image data, $width x $height"* ]] ||
    fail "PNG ${width}x${height} non valido: ${path#"$repo_root"/}"
}

validate_mobile_screenshot_set() {
  local root="$1"
  local width="$2"
  local height="$3"
  local locale
  local directory
  local page
  local png_count
  local total_png_count
  local expected_png_count
  for locale in "${mobile_screenshot_locales[@]}"; do
    directory="$root/$locale"
    [[ -d "$directory" ]] || fail "cartella screenshot mancante: ${directory#"$repo_root"/}"
    png_count="$(find "$directory" -maxdepth 1 -type f -name '*.png' | wc -l | tr -d ' ')"
    [[ "$png_count" -eq 3 ]] ||
      fail "attesi esattamente tre screenshot in ${directory#"$repo_root"/}"
    for page in "${mobile_screenshot_pages[@]}"; do
      validate_png_dimensions "$directory/$page.png" "$width" "$height"
    done
  done

  # Gavemo già verificà ogni cartella: el totale globale smaschera file legacy
  # o directory extra che altrimenti restaria fora dalla matrice approvata.
  total_png_count="$(find "$root" -type f -name '*.png' | wc -l | tr -d ' ')"
  expected_png_count=$((${#mobile_screenshot_locales[@]} * ${#mobile_screenshot_pages[@]}))
  [[ "$total_png_count" -eq "$expected_png_count" ]] ||
    fail "set screenshot mobile inatteso in ${root#"$repo_root"/}: attesi $expected_png_count PNG, trovati $total_png_count"
}

is_expected_product() {
  local candidate="$1"
  local expected
  for expected in "${expected_product_ids[@]}"; do
    [[ "$candidate" == "$expected" ]] && return 0
  done
  return 1
}

is_tip_locale() {
  local candidate="$1"
  local expected
  for expected in "${tip_locales[@]}"; do
    [[ "$candidate" == "$expected" ]] && return 0
  done
  return 1
}

cd "$repo_root"

version_value="$(sed -nE 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)[[:space:]]*$/\1+\2/p' pubspec.yaml)"
[[ -n "$version_value" ]] || fail "pubspec.yaml deve usare major.minor.patch+build"

# Ogni lingua dichiarata dall'app deve avere il catalogo ARB sorgente.
for language in "${supported_languages[@]}"; do
  require_nonempty "$repo_root/lib/l10n/app_${language}.arb"
done

# I limiti conservativi rispecchiano i campi delle tre console.
for locale in "${app_store_locales[@]}"; do
  root="$repo_root/app_store/metadata/$locale"
  for name in name subtitle promotional_text description keywords privacy_url support_url marketing_url release_notes; do
    require_nonempty "$root/$name.txt"
  done
  validate_file_length "$root/name.txt" 30
  validate_file_length "$root/subtitle.txt" 30
  validate_file_length "$root/promotional_text.txt" 170
  validate_file_length "$root/description.txt" 4000
  validate_file_length "$root/keywords.txt" 100
  validate_file_length "$root/release_notes.txt" 4000
  validate_https_url "$root/privacy_url.txt"
  validate_https_url "$root/support_url.txt"
  validate_https_url "$root/marketing_url.txt"
done

for locale in "${play_store_locales[@]}"; do
  root="$repo_root/play_store/metadata/$locale"
  for name in title short_description full_description privacy_policy_url release_notes; do
    require_nonempty "$root/$name.txt"
  done
  validate_file_length "$root/title.txt" 30
  validate_file_length "$root/short_description.txt" 80
  validate_file_length "$root/full_description.txt" 4000
  validate_file_length "$root/release_notes.txt" 500
  validate_https_url "$root/privacy_policy_url.txt"
done

for locale in "${microsoft_store_locales[@]}"; do
  root="$repo_root/microsoft_store/metadata/$locale"
  for name in title short_description description release_notes; do
    require_nonempty "$root/$name.txt"
  done
  validate_file_length "$root/title.txt" 50
  validate_file_length "$root/short_description.txt" 100
  validate_file_length "$root/description.txt" 10000
  validate_file_length "$root/release_notes.txt" 1500

  for index in 01 02 03; do
    screenshot_list="$(find "$repo_root/microsoft_store/screenshots/$locale" -maxdepth 1 -type f -name "${index}-*.png" -print)"
    screenshot_count="$(printf '%s\n' "$screenshot_list" | sed '/^$/d' | wc -l | tr -d ' ')"
    [[ "$screenshot_count" -eq 1 ]] ||
      fail "atteso uno screenshot Microsoft $index per $locale"
    validate_png_dimensions "$screenshot_list" 1366 768
  done
done

validate_mobile_screenshot_set "$repo_root/app_store/screenshots" 1242 2688
validate_mobile_screenshot_set "$repo_root/app_store/screenshots_ipad" 2064 2752
validate_mobile_screenshot_set "$repo_root/play_store/graphics/phone-screenshots" 1242 2484

# Gli ID nel codice devono coincidere esattamente con il catalogo approvato.
code_product_ids="$(sed -nE "s/.*'(rubrica_tip_[^']+)'.*/\1/p" lib/services/tip_jar_service.dart | sort)"
expected_product_list="$(printf '%s\n' "${expected_product_ids[@]}" | sort)"
[[ "$code_product_ids" == "$expected_product_list" ]] ||
  fail "gli ID delle mance nel codice non coincidono con i quattro ID attesi"

require_nonempty "$repo_root/store/mobile-tip-products.csv"
expected_header='product_id,locale,reference_price_eur,name,description'
actual_header="$(sed -n '1p' store/mobile-tip-products.csv)"
[[ "$actual_header" == "$expected_header" ]] || fail "intestazione CSV mance non valida"

tip_metadata_rows="$(tail -n +2 store/mobile-tip-products.csv | wc -l | tr -d ' ')"
[[ "$tip_metadata_rows" -eq 16 ]] ||
  fail "attese 16 righe di metadata mance, trovate $tip_metadata_rows"

duplicate_pairs="$(tail -n +2 store/mobile-tip-products.csv | cut -d, -f1,2 | sort | uniq -d)"
[[ -z "$duplicate_pairs" ]] || fail "coppie prodotto/lingua duplicate nel CSV mance"

while IFS=, read -r product_id locale price name description extra; do
  [[ -z "${extra:-}" ]] || fail "riga CSV con più di cinque campi: $product_id/$locale"
  is_expected_product "$product_id" || fail "ID prodotto inatteso: $product_id"
  is_tip_locale "$locale" || fail "lingua prodotto inattesa: $locale"
  [[ "$price" =~ ^[0-9]+\.[0-9]{2}$ ]] || fail "prezzo di riferimento non valido: $product_id/$locale"
  [[ -n "$name" && -n "$description" ]] || fail "nome o descrizione vuoti: $product_id/$locale"
  name_length="$(character_count "$name")"
  description_length="$(character_count "$description")"
  [[ "$name_length" -le 30 ]] || fail "nome Apple oltre 30 caratteri: $product_id/$locale"
  [[ "$description_length" -le 45 ]] || fail "descrizione Apple oltre 45 caratteri: $product_id/$locale"
done < <(tail -n +2 store/mobile-tip-products.csv)

for product_id in "${expected_product_ids[@]}"; do
  for locale in "${tip_locales[@]}"; do
    pair_count="$(awk -F, -v id="$product_id" -v loc="$locale" '$1 == id && $2 == loc {count++} END {print count + 0}' store/mobile-tip-products.csv)"
    [[ "$pair_count" -eq 1 ]] || fail "coppia prodotto/lingua mancante: $product_id/$locale"
  done
done

echo "Repository metadata complete: $version_value, 4 lingue, 3 cataloghi, 4 mance."
