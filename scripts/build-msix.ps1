param(
    [switch]$SkipBuild
)

# Crea el pacchetto Store usando sempre versione e build del pubspec.
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pubspecPath = Join-Path $repoRoot 'pubspec.yaml'
$pubspec = Get-Content -Raw -Path $pubspecPath
$versionMatch = [regex]::Match(
    $pubspec,
    '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$'
)

if (-not $versionMatch.Success) {
    throw "Versione non valida in $pubspecPath: richiesto major.minor.patch+build."
}

$versionParts = 1..4 | ForEach-Object {
    [int]$versionMatch.Groups[$_].Value
}

if ($versionParts | Where-Object { $_ -gt 65535 }) {
    throw 'Ogni componente della versione MSIX deve essere compreso tra 0 e 65535.'
}

$msixVersion = $versionParts -join '.'

Push-Location $repoRoot
try {
    if (-not $SkipBuild) {
        flutter build windows --release
    }

    # El quarto numero conserva el build Flutter, cussì ogni upload xe crescente.
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
