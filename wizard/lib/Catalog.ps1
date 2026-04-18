function Get-Catalog {
    param([string]$TianDir)
    $catalogPath = Join-Path $TianDir "config\catalog.json"
    if (-not (Test-Path $catalogPath)) {
        throw "Catalog not found at: $catalogPath"
    }
    return Get-Content $catalogPath -Raw | ConvertFrom-Json
}
