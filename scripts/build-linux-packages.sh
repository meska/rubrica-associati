#!/usr/bin/env bash

set -euo pipefail

# Prepara tutti i formati Linux dalla stessa build Flutter, senza versioni duplicate.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pubspec_path="$repo_root/pubspec.yaml"
bundle_dir="$repo_root/build/linux/x64/release/bundle"
output_dir="$repo_root/build/linux/packages"
desktop_file="$repo_root/packaging/linux/it.meska.rubricaassociati.desktop"
logo_file="$repo_root/assets/branding/rubrica-associati-logo.png"

version_line="$(sed -nE 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)[[:space:]]*$/\1 \2/p' "$pubspec_path")"
read -r app_version build_number <<<"$version_line"

if [[ -z "${app_version:-}" || -z "${build_number:-}" ]]; then
  echo "Versione non valida in $pubspec_path: richiesto major.minor.patch+build." >&2
  exit 1
fi

if [[ ! -x "$bundle_dir/rubrica_associati" ]]; then
  echo "Build Linux non trovata in $bundle_dir; eseguire prima flutter build linux --release." >&2
  exit 1
fi

for required_command in convert curl dpkg-deb sha256sum; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Comando richiesto non disponibile: $required_command" >&2
    exit 1
  fi
done

install -d "$output_dir"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

icon_file="$temporary_dir/it.meska.rubricaassociati.png"
convert "$logo_file" -resize 512x512 "$icon_file"

# El tool xe fissà a una release e verificà prima de eseguirlo.
linuxdeploy_version="1-alpha-20251107-1"
linuxdeploy_sha256="c20cd71e3a4e3b80c3483cef793cda3f4e990aca14014d23c544ca3ce1270b4d"
linuxdeploy_path="${LINUXDEPLOY_BIN:-$temporary_dir/linuxdeploy-x86_64.AppImage}"

if [[ -z "${LINUXDEPLOY_BIN:-}" ]]; then
  curl \
    --fail \
    --location \
    --retry 3 \
    --output "$linuxdeploy_path" \
    "https://github.com/linuxdeploy/linuxdeploy/releases/download/$linuxdeploy_version/linuxdeploy-x86_64.AppImage"
fi

echo "$linuxdeploy_sha256  $linuxdeploy_path" | sha256sum --check --status
chmod +x "$linuxdeploy_path"

app_dir="$temporary_dir/AppDir"
install -d \
  "$app_dir/usr/bin" \
  "$app_dir/usr/share/applications" \
  "$app_dir/usr/share/icons/hicolor/512x512/apps"
cp -a "$bundle_dir/." "$app_dir/usr/bin/"
ln -s rubrica_associati "$app_dir/usr/bin/rubrica-associati"
install -m 0644 "$desktop_file" "$app_dir/usr/share/applications/"
install -m 0644 "$icon_file" "$app_dir/usr/share/icons/hicolor/512x512/apps/"

appimage_output="$output_dir/rubrica-associati-linux-x86_64.AppImage"
rm -f "$appimage_output"
OUTPUT="$appimage_output" VERSION="$app_version" APPIMAGE_EXTRACT_AND_RUN=1 \
  "$linuxdeploy_path" \
  --appdir "$app_dir" \
  --executable "$app_dir/usr/bin/rubrica_associati" \
  --desktop-file "$desktop_file" \
  --icon-file "$icon_file" \
  --output appimage

debian_version="$app_version-$build_number"
debian_root="$temporary_dir/debian"
install -d \
  "$debian_root/DEBIAN" \
  "$debian_root/opt/rubrica-associati" \
  "$debian_root/usr/bin" \
  "$debian_root/usr/share/applications" \
  "$debian_root/usr/share/icons/hicolor/512x512/apps"
cp -a "$bundle_dir/." "$debian_root/opt/rubrica-associati/"
ln -s /opt/rubrica-associati/rubrica_associati "$debian_root/usr/bin/rubrica-associati"
install -m 0644 "$desktop_file" "$debian_root/usr/share/applications/"
install -m 0644 "$icon_file" "$debian_root/usr/share/icons/hicolor/512x512/apps/"
sed "s/@VERSION@/$debian_version/g" \
  "$repo_root/packaging/linux/debian/control.in" \
  >"$debian_root/DEBIAN/control"

deb_output="$output_dir/rubrica-associati_${debian_version}_amd64.deb"
dpkg-deb --build --root-owner-group "$debian_root" "$deb_output"

tar_output="$output_dir/rubrica-associati-linux-x64.tar.gz"
tar -C "$bundle_dir" -czf "$tar_output" .

# I checksum coprono esattamente i tre file distribuiti.
(
  cd "$output_dir"
  sha256sum \
    "$(basename "$appimage_output")" \
    "$(basename "$deb_output")" \
    "$(basename "$tar_output")" \
    >SHA256SUMS-linux-x64.txt
)

printf 'Pacchetti Linux pronti in %s\n' "$output_dir"
