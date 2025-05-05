# Import shared.ps1
. ([System.IO.Path]::Combine($PSScriptRoot, 'shared.ps1'))

################
# FLOW DIAGRAM #
################


function Get-ConditionalAccessFlowChart  {
    param (
        $MaesterTests
    )

    Write-OutputInfo "Generating flow chart"

    $CAJSON = @{} # create empty object

    # Get unique UPNs
    $uniqueUPNs = $MaesterTests | Select-Object -ExpandProperty UPN -Unique

    foreach ($UPN in $uniqueUPNs) {
        $arr = @()
        $uniqueTestsByApp = $MaesterTests | Where-Object { $_.UPN -eq $UPN} | Sort-Object appName -Unique

        foreach ($test1 in $uniqueTestsByApp) {
            $arr1 = @()
            $uniqueTestsByClientApp = $MaesterTests | Where-Object { $_.UPN -eq $UPN -and $_.appName -eq $test1.appName} | Sort-Object clientApp -Unique

            foreach ($test2 in $uniqueTestsByClientApp) {
                $arr2 = @()
                $uniqueTestsByDevicePlatform = $MaesterTests | Where-Object { $_.UPN -eq $UPN -and $_.appName -eq $test2.appName -and $_.clientApp -eq $test2.clientApp} | Sort-Object devicePlatform -Unique

                foreach ($test3 in $uniqueTestsByDevicePlatform) {
                    $arr3 = @()
                    $uniqueTestsByIPRange = $MaesterTests | Where-Object { $_.UPN -eq $UPN -and $_.appName -eq $test3.appName -and $_.clientApp -eq $test3.clientApp -and $_.IPRange -eq $test3.IPRange} | Sort-Object IPRange -Unique

                    foreach ($test4 in $uniqueTestsByIPRange) {
                        #
                        $arr4 = @()
                        $uniqueTestsByUserRisk = $MaesterTests | Where-Object { $_.UPN -eq $UPN -and $_.appName -eq $test4.appName -and $_.clientApp -eq $test4.clientApp -and $_.IPRange -eq $test4.IPRange -and $_.userRisk -eq $test4.userRisk} | Sort-Object userRisk -Unique

                        foreach ($test5 in $uniqueTestsByUserRisk) {
                            $finalAction = ($test5.inverted) ? @("no $($test5.expectedControl) ($($test5.CAPolicyName))") : @("$($test5.expectedControl) ($($test5.CAPolicyName))") # include 'not' if the test is inverted

                            if ($test5.userRisk -eq '/') {
                                $arr4 += $finalAction
                            } else {
                                $arr4 += @{
                                    "User risk: $($test5.userRisk)" = $finalAction
                                } 
                            }  
                        }

                        if ($test4.IPRange -eq '/') {
                            $arr3 += $arr4
                        } else {
                            $arr3 += @{
                                "IP: $($test4.IPRange)" = $arr4
                            } 
                        }  
                    }
                    

                    if ($test3.devicePlatform -eq '/') {
                        $arr2 += $arr3
                    } else {
                        $arr2 += @{
                            "OS: $($test3.devicePlatform)" = $arr3
                        }
                    }
                }

                $arr1 += @{
                    "$($test2.clientApp) auth" = $arr2
                }
            }

            $arr += @{
                $test1.appName = $arr1
            }

        }

        $CAJSON[$UPN] = $arr
    }

    return $CAJSON
}