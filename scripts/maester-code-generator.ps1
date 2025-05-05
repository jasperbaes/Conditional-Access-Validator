. ([System.IO.Path]::Combine($PSScriptRoot, 'shared.ps1'))

##########################
# MAESTER TEST GENERATOR #
##########################

function Create-MaesterCode {
    param (
        $MaesterTests
    )

    Write-OutputInfo "Translating to the Maester code"
    $templateMaester = @"

    Describe "$($ORGANIZATIONNAME).ConditionalAccess" {`n
"@

    foreach ($MaesterTest in $MaesterTests) { 
        $templateMaester += "`n`tIt `"$($MaesterTest.testTitle)`" {`n"
        $templateMaester += "`t`t`$userId = `'$($MaesterTest.userID)`' # $($MaesterTest.UPN) `n"
        $templateMaester += "`t`t`$policiesEnforced = Test-MtConditionalAccessWhatIf -UserId `$userId "
        $templateMaester += "-IncludeApplications `'$($MaesterTest.appID)`' "

        if ($MaesterTest.clientApp -ne "all") { # don't add to the test if 'all'
            $templateMaester += "-ClientAppType `'$($MaesterTest.clientApp)`' "
        } else {
            $MaesterTest.clientApp = '/' # set als '/' for the HTML report
        }

        if ($MaesterTest.IPRange -and $MaesterTest.IPRange -ne "All") {
            $templateMaester += "-Country 'FR' -IpAddress `'$($MaesterTest.IPRange)`' "
        } else {
            $MaesterTest.IPRange = '/' # set als '/' for the HTML report
        }

        if ($MaesterTest.devicePlatform -and $MaesterTest.devicePlatform -ne "All") {
            $templateMaester += "-DevicePlatform `'$($MaesterTest.devicePlatform)`' "
        } else {
            $MaesterTest.devicePlatform = '/' # set als '/' for the HTML report
        }

        if ($MaesterTest.userRisk -and $MaesterTest.userRisk -ne "All") { # the first letter must be uppercase (e.g.: 'Low', 'Medium', 'High')
            $templateMaester += "-UserRiskLevel `'$($MaesterTest.userRisk.Substring(0,1).ToUpper() + $MaesterTest.userRisk.Substring(1))`' "
        } else {
            $MaesterTest.userRisk = '/' # set als '/' for the HTML report
        }

        $templateMaester += "`n"

        if ($MaesterTest.inverted -eq $true) {
            $templateMaester += "`t`t`$policiesEnforced.grantControls.builtInControls | Should -Not -Contain `'$($MaesterTest.expectedControl)`' `n"
        } else {
            $templateMaester += "`t`t`$policiesEnforced.grantControls.builtInControls | Should -Contain `'$($MaesterTest.expectedControl)`' `n"
        }

        $templateMaester += "`t}`n"
    }

    $templateMaester += "}"

    Write-OutputSuccess "Translated to the Maester test layout"

    return $templateMaester
}    