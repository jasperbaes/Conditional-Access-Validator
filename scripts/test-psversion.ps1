[CmdletBinding()]
param()
    
    $minimumPSVersion = [Version]"7.0.0"
    $currentPSVersion = $PSVersionTable.PSVersion
    
    if ($currentPSVersion -lt $minimumPSVersion) {
        Write-Host "Error: This script requires PowerShell 7.0 or higher." -ForegroundColor Red
        Write-Host "Current PowerShell version: $($currentPSVersion)" -ForegroundColor Red
        Write-Host "Please install PowerShell 7 from https://github.com/PowerShell/PowerShell/releases" -ForegroundColor Yellow
        
        # Check if pwsh is installed but script was run in older version
        if (Get-Command pwsh -ErrorAction SilentlyContinue) {
            Write-Host "`nPowerShell 7 appears to be installed. You can run this script with:" -ForegroundColor Cyan
            Write-Host "pwsh -File `"$($MyInvocation.PSCommandPath)`"" -ForegroundColor Cyan

            # Ask if they want to relaunch with PowerShell 7
            do {
                $response = Read-Host "Would you like to run this script using PowerShell 7 now? (Y/N)"
            } while ($response -notmatch '^(Y|y|N|n)$')

            if ($response -match '^(Y|y)$') {
                Start-Process -FilePath "pwsh" -ArgumentList "-File `"$($MyInvocation.PSCommandPath)`"" -NoNewWindow
            } else {
                Write-Host "Script execution stopped." -ForegroundColor Yellow
            }
        }
        
        # Stop script execution
        exit
    }