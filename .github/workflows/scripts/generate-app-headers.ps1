#!/usr/bin/env pwsh

# Function for generating Figlet headers
function Generate-Headers {
    param (
        [string]$BaseDir,
        [string]$TargetSubdir,
        [string]$SearchPattern
    )

    $HeadersDir = Join-Path $BaseDir $TargetSubdir

    # Create headers directory if it doesn't exist
    if (-not (Test-Path $HeadersDir)) {
        New-Item -ItemType Directory -Path $HeadersDir -Force | Out-Null
    }

    # Remove existing header files
    Get-ChildItem -Path $HeadersDir -File | Remove-Item -Force

    # Determine search scope (recursive or not)
    if ($SearchPattern -eq "**") {
        $FileList = Get-ChildItem -Path $BaseDir -Filter "*.sh" -Recurse -File
    }
    else {
        $FileList = Get-ChildItem -Path $BaseDir -Filter "*.sh" -File
    }

    foreach ($Script in $FileList) {
        # Extract APP name from script
        $Content = Get-Content $Script.FullName -Raw
        if ($Content -match 'APP="([^"]+)"') {
            $AppName = $Matches[1]

            $OutputFile = Join-Path $HeadersDir $Script.BaseName

            # Generate figlet output
            try {
                $FigletOutput = & figlet -w 500 -f slant $AppName 2>&1

                if ($LASTEXITCODE -eq 0 -and $FigletOutput) {
                    $FigletOutput | Out-File -FilePath $OutputFile -Encoding utf8
                    Write-Host "Generated: $OutputFile" -ForegroundColor Green
                }
                else {
                    Write-Host "Figlet failed for $AppName in $($Script.Name)" -ForegroundColor Yellow
                }
            }
            catch {
                Write-Host "Error running figlet for $AppName : $_" -ForegroundColor Red
            }
        }
        else {
            Write-Host "No APP name found in $($Script.Name), skipping." -ForegroundColor Gray
        }
    }
}

# Check if figlet is available
try {
    $null = Get-Command figlet -ErrorAction Stop
}
catch {
    Write-Host "Error: figlet is not installed or not in PATH" -ForegroundColor Red
    Write-Host "`nInstallation options:" -ForegroundColor Yellow
    Write-Host "1. Using Scoop (recommended):" -ForegroundColor Cyan
    Write-Host "   scoop install figlet" -ForegroundColor White
    Write-Host "`n2. Manual download:" -ForegroundColor Cyan
    Write-Host "   Download from: https://github.com/cmatsuoka/figlet/releases" -ForegroundColor White
    Write-Host "   Extract and add to PATH" -ForegroundColor White
    Write-Host "`n3. Using WSL:" -ForegroundColor Cyan
    Write-Host "   Run the bash version: bash generate-app-headers.sh" -ForegroundColor White
    exit 1
}

# Change to script directory
$ScriptDir = Split-Path -Parent $PSCommandPath
$RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $ScriptDir))
Set-Location $RepoRoot

Write-Host "Processing ct/ directory..." -ForegroundColor Cyan
Generate-Headers -BaseDir ".\ct" -TargetSubdir "headers" -SearchPattern "*"

Write-Host "`nProcessing tools/ directory..." -ForegroundColor Cyan
Generate-Headers -BaseDir ".\tools" -TargetSubdir "headers" -SearchPattern "**"

Write-Host "`nProcessing vm/ directory..." -ForegroundColor Cyan
Generate-Headers -BaseDir ".\vm" -TargetSubdir "headers" -SearchPattern "*"

Write-Host "`nCompleted processing all sections." -ForegroundColor Green
