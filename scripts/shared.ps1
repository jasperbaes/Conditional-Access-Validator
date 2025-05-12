function Write-OutputError { param ( [string]$Message ) Write-Host " [" -ForegroundColor White -NoNewline; Write-Host "-" -ForegroundColor Red -NoNewline; Write-Host "] $Message" -ForegroundColor White }
function Write-OutputSuccess { param ( [string]$Message ) Write-Host " [" -ForegroundColor White -NoNewline; Write-Host "+" -ForegroundColor Green -NoNewline; Write-Host "] $Message" -ForegroundColor White }
function Write-OutputInfo { param ( [string]$Message ) Write-Host " [" -ForegroundColor White -NoNewline; Write-Host "i" -ForegroundColor Blue -NoNewline; Write-Host "] $Message" -ForegroundColor White }

function Get-AllPagesFromMicrosoftGraph {
    param (
        $URL
    )
    
    $allPages = @()

    $aadUsers = Invoke-MgGraphRequest -Method GET $URL
    $allPages += $aadUsers.value

    if ($aadUsers.'@odata.nextLink') {
        do {

            $aadUsers = Invoke-MgGraphRequest -Method GET $aadUsers.'@odata.nextLink'
            $allPages += $aadUsers.value

        } until (
            !$aadUsers.'@odata.nextLink'
        )    
    }

    return $allPages
}