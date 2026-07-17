param(
    [switch]$SkipBuild
)

# Crea el pacchetto Store usando la versione semantica del pubspec.
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pubspecPath = Join-Path $repoRoot 'pubspec.yaml'
$pubspec = Get-Content -Raw -Path $pubspecPath
$versionMatch = [regex]::Match(
    $pubspec,
    '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$'
)

if (-not $versionMatch.Success) {
    throw "Versione non valida in ${pubspecPath}: richiesto major.minor.patch+build."
}

$versionParts = 1..3 | ForEach-Object {
    [int]$versionMatch.Groups[$_].Value
}

if ($versionParts | Where-Object { $_ -gt 65535 }) {
    throw 'Ogni componente della versione MSIX deve essere compreso tra 0 e 65535.'
}

# Microsoft Store pretende la revisione (quarto componente) sempre a zero.
$msixVersion = ($versionParts + 0) -join '.'

Push-Location $repoRoot
try {
    if (-not $SkipBuild) {
        flutter build windows --release
    }

    # El build Flutter resta canonico per mobile; qua conta la versione semantica.
    dart run msix:create --build-windows false --version $msixVersion

    $package = Get-ChildItem `
        -Path (Join-Path $repoRoot 'build/windows') `
        -Filter '*.msix' `
        -File `
        -Recurse |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $package) {
        throw 'Il comando msix non ha generato alcun pacchetto.'
    }

    Write-Output "MSIX pronto: $($package.FullName) (versione $msixVersion)"
}
finally {
    Pop-Location
}
