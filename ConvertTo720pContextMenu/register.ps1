$ErrorActionPreference = 'Stop'

reg import "$PSScriptRoot\convert-to-720p.reg"
Write-Host "OK  Convert to 720p context menu"
