# Shared helpers loaded by every .Tests.ps1 file

$script:TIAN_ROOT = Resolve-Path (Join-Path $PSScriptRoot "../../..") | Select-Object -ExpandProperty Path

function Get-TianRoot { return $script:TIAN_ROOT }

# Stub for Append-Log so lib modules run without WinForms
function global:Append-Log {
    param($LogBox, [string]$Message, [string]$Color = "normal")
    # Captured in tests via $script:LogMessages
    if ($null -ne $script:LogMessages) { $script:LogMessages += $Message }
}

# Fake progress bar object
function New-FakeProgressBar {
    $v = 0
    $pb = [PSCustomObject]@{}
    Add-Member -InputObject $pb -MemberType NoteProperty -Name Value -Value 0
    return $pb
}

# Create a temp dir that is cleaned up automatically
function New-TestTempDir {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

# Write JSON to a file helper
function Write-TestJson {
    param([string]$Path, [object]$Data)
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Data | ConvertTo-Json -Depth 10 | Set-Content $Path -Encoding UTF8
}
