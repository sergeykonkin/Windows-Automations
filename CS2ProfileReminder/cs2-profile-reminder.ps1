Import-Module BurntToast

$shown = $false

while ($true) {
    $cs2 = Get-Process -Name "cs2" -ErrorAction SilentlyContinue

    if ($cs2 -and -not $shown) {
        New-BurntToastNotification -Text "CS2", "Keyboard Profile!"
        $shown = $true
    }

    if (-not $cs2) {
        $shown = $false
    }

    Start-Sleep -Seconds 5
}
