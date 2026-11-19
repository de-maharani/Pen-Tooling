# ==============================================================
# Unquoth.ps1 — Unquoted service path writability checker
# ==============================================================
#
# USAGE:
#   1. Enumerate service binaries:
#        wmic service get name,pathname | findstr /i /v "C:\Windows\"
#      Look for paths with spaces that are NOT wrapped in quotes.
#
#   2. Set $TargetPath below to that raw path, then run:
#        powershell -ExecutionPolicy Bypass -File .\Unquoth.ps1
#
# HOW TO READ THE OUTPUT:
#   [+] WRITABLE  -> you can write here; path resolver may execute
#                    a binary you drop in this directory
#   [-] NOT WRITABLE -> resolver would fall through to the next token
#
# The first WRITABLE directory below the "real" install dir is
# typically your hijack target. Directories you can write to that
# are ABOVE the install dir usually don't matter — the resolver
# tries progressively longer prefixes of the path.
# ==============================================================

# CONFIGURE: full path to the target service binary
# Example: C:\Program Files\Some App\svc.exe (no surrounding quotes)
$TargetPath = "C:\Path\To\Your App\service.exe"

$CurrentDir = Split-Path -Parent $TargetPath

Write-Host "`n[*] Checking write access up the tree for:" -ForegroundColor Cyan
Write-Host "    $TargetPath" -ForegroundColor Cyan
Write-Host "--------------------------------------------------"

while ($CurrentDir) {
    $TestFile = Join-Path $CurrentDir "wrtest_$(Get-Random).tmp"
    $Writable = $false

    try {
        # Try to create a dummy file
        $null = New-Item -ItemType File -Path $TestFile -ErrorAction Stop
        $Writable = $true
        # Clean up immediately if successful
        Remove-Item -Path $TestFile -Force -ErrorAction SilentlyContinue
    } catch {
        $Writable = $false
    }

    if ($Writable) {
        Write-Host "[+] WRITABLE     : $CurrentDir" -ForegroundColor Green
    } else {
        Write-Host "[-] NOT WRITABLE : $CurrentDir" -ForegroundColor Red
    }

    # Move up to the parent directory
    $CurrentDir = Split-Path -Parent $CurrentDir
}
Write-Host "--------------------------------------------------`n"
