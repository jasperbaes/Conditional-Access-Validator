# Import shared.ps1
. ([System.IO.Path]::Combine($PSScriptRoot, 'shared.ps1'))

# Returns the UPN by a given user ID
function Get-UPNbyID {
    param (
        [string]$userID
    )

    try {
        $user = Invoke-MgGraphRequest -Method GET ('https://graph.microsoft.com/v1.0/users/' + $userID + '?$select=userPrincipalName')
        
        if ($user) {
            return $user.userPrincipalName
        } else {
            return "N/A"
        }
    } catch {
        return "N/A"
    }
}

# Returns 5 random users of the tenant that are not in the array $excludeUsers or member of the groups in $excludeGroups
function Get-RandomUsersOfTheTenant {
    param (
        $scope,
        $excludeUsers,
        $excludeGroups
    )

    try {
        [array]$returnedUsers = @() # create empty array

        if ($scope -eq 'tenant') {
            $users = Invoke-MgGraphRequest -Method GET ('https://graph.microsoft.com/v1.0/users?$select=id,userPrincipalName')
            $usersList = $users.value
        } else { # scope is a groupID
            $users = Invoke-MgGraphRequest -Method GET ('https://graph.microsoft.com/v1.0/groups/' + $scope + '?$select=id,displayName&$expand=members')
            $usersList = $users.members
        }

        $hasChosenRandomUsers = $false
        
        # If the group has more than 5 members, then choose 5 random members
        if ($usersList.Count -gt 5) {
            $usersList = $usersList | Sort-Object userPrincipalName -Unique | Get-Random -Count 5   
            $hasChosenRandomUsers = $true
        }

        # TODO: checken ofdat deze users niet in $excludeUsers of $excludeGroups zitten

        foreach ($user in $usersList) {
            $returnedUsers += @{
                userID = $user.id
                UPN = ($hasChosenRandomUsers -eq $true) ? "$($user.userPrincipalName) (random)" : $user.userPrincipalName # adds '(random)' if the user is randomly chosen from the scope (tenant or an included group)
            }
        }

        return $returnedUsers
    } catch {}
}

function Get-RandomGuestsOfTheTenant {
    try {
        [array]$returnedUsers = @() # create empty array

        $users = Invoke-MgGraphRequest -Method GET ('https://graph.microsoft.com/v1.0/users?$select=id,userPrincipalName&$filter=userType eq ' + "'Guest'")
        $usersList = $users.value

        # If there are more than 2 guests, get 2 random
        if ($usersList.Count -gt 2) {
            $usersList = $usersList | Sort-Object userPrincipalName -Unique | Get-Random -Count 2   
            $hasChosenRandomUsers = $true
        }

        foreach ($user in $usersList) {
            $returnedUsers += @{
                userID = $user.id
                UPN = ($hasChosenRandomUsers -eq $true) ? "$($user.userPrincipalName) (random)" : $user.userPrincipalName # adds '(random)' if the user is randomly chosen from the scope (tenant or an included group)
            }
        }

        return $returnedUsers
    } catch {}
}

function Get-CAPUsers {
    param (
        [Parameter(Mandatory=$true)]
        $CAUsersObject
    )

    $allUsers = @() # create empty array

    [array]$includeUsers = $CAUsersObject.includeUsers
    [array]$excludeUsers = $CAUsersObject.excludeUsers
    [array]$includeGroups = $CAUsersObject.includeGroups
    [array]$excludeGroups = $CAUsersObject.excludeGroups
    [array]$includeGuests = $CAUsersObject.includeGuestsOrExternalUsers

    # add all included users. If the policy is scope to 'All', then add 5 random users
    foreach ($userID in $includeUsers) {
        if ($userID -eq "All") {
            [array]$randomUsersOfTheTenant = Get-RandomUsersOfTheTenant 'tenant' $excludeUsers $excludeGroups
            
            foreach ($randomUser in $randomUsersOfTheTenant) {
                $allUsers += @{
                    userID = $randomUser.userID
                    UPN = $randomUser.UPN
                    type = "included"
                }
            }
        } else {
            $UPN = Get-UPNbyID $userID
            if ($UPN -ne "N/A") {
                $allUsers += @{
                    userID = $userID
                    UPN = $UPN
                    type = "included"
                }
            }
        }
    }

    # add all excluded users
    foreach ($userID in $excludeUsers) {  
        if ($userID -ne "All") {
            $UPN = Get-UPNbyID $userID
            if ($UPN -ne "N/A") {
                $allUsers += @{
                    userID = $userID
                    UPN = Get-UPNbyID $userID
                    type = "excluded"
                }
            }
        }
    }

    # For an included group, add 5 random users
    foreach ($groupID in $includeGroups) {
        [array]$randomUsersOfTheTenant = Get-RandomUsersOfTheTenant $groupID $excludeUsers $excludeGroups

        foreach ($randomUser in $randomUsersOfTheTenant) {
            $allUsers += @{
                userID = $randomUser.userID
                UPN = $randomUser.UPN
                type = "included"
            }
        }
    }

    # For an included group, add 5 random users
    foreach ($groupID in $excludeGroups) {
        [array]$randomUsersOfTheTenant = Get-RandomUsersOfTheTenant $groupID @() @()

        foreach ($randomUser in $randomUsersOfTheTenant) {
            $allUsers += @{
                userID = $randomUser.userID
                UPN = $randomUser.UPN
                type = "excluded"
            }
        }
    }

    # If scope to guests, add 2 random guests
    if ($CAUsersObject.includeGuestsOrExternalUsers) {
        [array]$randomGuestsOfTheTenant = Get-RandomGuestsOfTheTenant

        foreach ($randomGuest in $randomGuestsOfTheTenant) {
            $allUsers += @{
                userID = $randomGuest.userID
                UPN = $randomGuest.UPN
                type = "included"
            }
        }
        
    }

    return $allUsers
}

# Returns the UPN by a given user ID
function Get-AppNamebyID {
    param (
        [string]$appID
    )

    try {
        # Try if the application is a Service Principal
        $app = Invoke-MgGraphRequest -Method GET ('https://graph.microsoft.com/v1.0/servicePrincipals/' + $appID)
        
        if ($app) {
            return $app.displayName
        }
    } catch {
        try {
            # When not a Service Principal, try if the application is a application template
            $app2 = Invoke-MgGraphRequest -Method GET ('https://graph.microsoft.com/v1.0/applicationTemplates/' + $appID)
            return $app2.displayName
            
        } catch {
            try {
                # When not a Service Principal and not a template, try if the application is an app registration
                $app3 = Invoke-MgGraphRequest -Method GET ('https://graph.microsoft.com/v1.0/applications?$filter=appId eq ' + "'" + $appID + "'")
                return $app3.value[0].displayName
            } catch {            
                return "N/A"
            }
        }
    }
}

function Get-CAPApplications {
    param (
        [Parameter(Mandatory=$true)]
        $CAApplicationsObject
    )

    $allApplications = @() # create empty array

    [array]$includeApplications = $CAApplicationsObject.includeApplications
    [array]$excludeApplications = $CAApplicationsObject.excludeApplications

    # if 'All' applications are included, or the application group 'Office365' is included, then add these applications
    if ($includeApplications -contains "All" -or $includeApplications -contains "Office365") {
        $allApplications += @{
            applicationID = "00000002-0000-0ff1-ce00-000000000000"
            applicationName = "Office 365 Exchange Online"
            type = "included"
        }
        $allApplications += @{
            applicationID = "00000003-0000-0ff1-ce00-000000000000"
            applicationName = "Office 365 SharePoint Online"
            type = "included"
        }
        $allApplications += @{
            applicationID = "00000006-0000-0ff1-ce00-000000000000"
            applicationName = "Office 365 Portal"
            type = "included"
        }
    }

    # if 'All' applications are excluded, or the application group 'Office365' is excluded, then add these applications
    if ($excludeApplications -contains "All" -or $excludeApplications -contains "Office365") {
        $allApplications += @{
            applicationID = "00000002-0000-0ff1-ce00-000000000000"
            applicationName = "Office 365 Exchange Online"
            type = "excluded"
        }
        $allApplications += @{
            applicationID = "00000003-0000-0ff1-ce00-000000000000"
            applicationName = "Office 365 SharePoint Online"
            type = "excluded"
        }
        $allApplications += @{
            applicationID = "00000006-0000-0ff1-ce00-000000000000"
            applicationName = "Office 365 Portal"
            type = "excluded"
        }
    }

    # add the first 3 included applications
    $maxApplications = 3
    $addedCount = 0

    foreach ($appID in $includeApplications) {
        if ($appID -ne "All" -and $appID -ne "Office365") {
            if ($addedCount -lt $maxApplications) {
                $appName = Get-AppNamebyID $appID
                if ($appName -ne "N/A" -and $appName -ne "None") {
                    $allApplications += @{
                        applicationID = $appID
                        applicationName = $appName
                        type = "included"
                    }
                    $addedCount++
                }
            } else {
                break
            }
        }
    }
    

    # add the first 3 excluded applications
    $maxApplications = 3
    $addedCount = 0

    foreach ($appID in $excludeApplications) { 
        if ($appID -ne "All" -and $appID -ne "Office365") {
            if ($addedCount -lt $maxApplications) {
                $appName = Get-AppNamebyID $appID
                if ($appName -ne "N/A" -and $appName -ne "None") {
                    $allApplications += @{
                        applicationID = $appID
                        applicationName = $appName
                        type = "excluded"
                    }
                    $addedCount++
                }
            } else {
                break
            }
        }
    }

    return $allApplications
}

function Generate-MaesterTest {
    param (
        $inverted, # if 'inverted' is true, then the Maester test should include a -Not
        $expectedControl, # 'expectedControl' can be 'block' or 'mfa' or 'passwordChange' or 'compliantDevice'
        $testTitle,
        $CAPolicyID,
        $CAPolicyName,
        $userID,
        $UPN,
        $appID,
        $appName,
        $clientApp,
        $IPRange,
        $devicePlatform,
        $userRisk,
        $signInRisk,
        $userAction
    )

    return New-Object PSObject -Property @{
        inverted = $inverted
        expectedControl = $expectedControl
        testTitle = $testTitle
        CAPolicyID = $CAPolicyID
        CAPolicyName = $CAPolicyName
        userID = $userID
        UPN = $UPN
        appID = $appID
        appName = $appName
        clientApp = $clientApp
        IPRange = $IPRange
        devicePlatform = $devicePlatform
        userRisk = $userRisk
        signInRisk = $signInRisk
        userAction = $userAction
    }
}

# This function returns all included and excluded IP addresses in 1 array, based on the included and excluded Named Locations
function Get-IPRanges {
    param (
        $includedLocationIDs,
        $excludedLocationIDs
    ) 
    
    $allIPRanges = @() # create empty array

    # if the CA policy has no included or excluded location set, then create an 'empty' IP range. This will not be added to the test itself. This object is required so it continues in the nested forEach loop
    if ($includedLocationIDs.count -eq 0 -or $includedLocationIDs.count -eq 0) {
        $allIPRanges += @{
            namedLocationName = 'All'
            IPrange = 'All'
            type = "included" # it does not matter if this is 'included' or 'excluded'. We will filter these out when generating the Maester test code
        }
    }

    # Loop over all includedLocations
    foreach ($locationID in $includedLocationIDs) {
        try {
            if ($locationID -eq "All") { # skip the one we added when the CA Policy does not use locations
                continue
            }

            # Lookup the named location
            $namedLocation = Invoke-MgGraphRequest -Method GET ('https://graph.microsoft.com/v1.0/identity/conditionalAccess/namedLocations/' + $locationID)
            
            if ($namedLocation) {
                foreach ($ipRange in $namedLocation.ipRanges) { 
                    $allIPRanges += @{
                        namedLocationName = $namedLocation.displayName
                        IPrange = $ipRange.cidrAddress
                        type = "included"
                    }
                }
            }
        } catch {}
    }

    foreach ($locationID in $excludedLocationIDs) {
        try {
            if ($locationID -eq "All") { # skip the one we added when the CA Policy does not use locations
                continue
            }

            # Lookup the named location
            $namedLocation = Invoke-MgGraphRequest -Method GET ('https://graph.microsoft.com/v1.0/identity/conditionalAccess/namedLocations/' + $locationID)
            
            if ($namedLocation) {
                foreach ($ipRange in $namedLocation.ipRanges) { 
                    $allIPRanges += @{
                        namedLocationName = $namedLocation.displayName
                        IPrange = $ipRange.cidrAddress
                        type = "excluded"
                    }
                }
            }
        } catch {}
    }

    return $allIPRanges
}


# This function returns all included and excluded device platforms
function Get-devicePlatforms {
    param (
        $includedDevicePlatforms,
        $excludedDevicePlatforms
    ) 
    
    $allPlatforms = @() # create empty array

    # if the CA policy has no included device platforms set, then create an 'empty' device list. This will not be added to the test itself. This object is required so it continues in the nested forEach loop
    if ($includedDevicePlatforms.count -eq 0) {
        $allPlatforms += @{
            OS = 'All'
            type = "included" # it does not matter if this is 'included' or 'excluded'. We will filter these out when generating the Maester test code
        }
    }

    # Loop over all includedDevicePlatforms and add as 'included'
    foreach ($devicePlatform in $includedDevicePlatforms) {
        $allPlatforms += @{
            OS = $devicePlatform
            type = "included"
        }
    }

    # if a device platform is included in the CA policy, then add every other device as 'excluded' This is required because if no device would be specified, the policy would always be triggered
    $allPossiblePlatforms = @('Android', 'iOS', 'windows', 'macOS', 'linux')
    if ($includedDevicePlatforms.count -ge 1) {
        foreach ($platform in $allPossiblePlatforms) {
            if (-not $includedDevicePlatforms -contains $platform) {
                $allPlatforms += @{
                    OS = $platform
                    type = "excluded"
                }
            }
        }
    }

     # Loop over all excludedDevicePlatforms
     foreach ($devicePlatform in $excludedDevicePlatforms) {
        $allPlatforms += @{
            OS = $devicePlatform
            type = "excluded"
        }
    }

    return $allPlatforms
}

# This function returns the name of a test. The test name only includes the test properties that are set.
function Create-TestName {
    param (
        $inverted, # if 'inverted' is true, then the Maester test should include a -Not
        $expectedControl, # 'expectedControl' can be 'block' or 'mfa' or 'passwordChange' or 'compliantDevice'
        $CAPolicyID,
        $CAPolicyName,
        $userID,
        $UPN,
        $appID,
        $appName,
        $clientApp,
        $IPRange,
        $devicePlatform,
        $userRisk,
        $signInRisk,
        $userAction
    )

    if ($inverted) {
        $testTitle = "no $expectedControl for $UPN on $appName"
    } else {
        $testTitle = "$expectedControl for $UPN on $appName"
    }
    

    if ($clientApp -ne "All") { # only add this property to the test title if it is set in the test
        if ($clientApp -eq 'other') {
            $clientApp = 'legacy'
        }
        $testTitle += " with $clientApp auth"
    }

    if ($IPRange -ne "All") { # only add this property to the test title if it is set in the test
        $testTitle += " from $IPRange"
    }

    if ($devicePlatform -ne "All") { # only add this property to the test title if it is set in the test
        $testTitle += " on $devicePlatform"
    }

    if ($userRisk -ne "All") { # only add this property to the test title if it is set in the test
        $testTitle += " with $userRisk user risk"
    }

    if ($signInRisk -ne "All") { # only add this property to the test title if it is set in the test
        $testTitle += " with $signInRisk signin risk"
    }

    if ($userAction -and $userAction -ne "" -and $userAction -ne "All") { # only add this property to the test title if it is set in the test
        $testTitle += " with $userAction user action"
    }

    return $testTitle
}

# This is the main function
function Create-Simulations {
    param(
        $conditionalAccessPolicies
    )

        
    Write-OutputInfo "Generating Maester tests"

    [array]$MaesterTests = @() # Create empty array
    $i = 0

    # Loop over all discovered Conditional Access Policies
    foreach ($conditionalAccessPolicy in $conditionalAccessPolicies) {
        # Write-OutputInfo "Generating Maester test for '$($conditionalAccessPolicy.displayName)' ($($conditionalAccessPolicy.id)) -- $($allUsers.count) users, $($allApplications.count) applications in test scope"
        $percentComplete = [math]::Round(($i / $conditionalAccessPolicies.Count) * 100)
        Write-Progress -Activity "     Generating Maester tests..." -Status "$percentComplete% Complete" -PercentComplete $percentComplete

        $testsCreatedForThisCAPolicy = 0

        # Get included and excluded users for tests
        [array]$allUsers = Get-CAPUsers $conditionalAccessPolicy.conditions.users
        [array]$allApplications = Get-CAPApplications $conditionalAccessPolicy.conditions.applications
        
        foreach ($user in $allUsers) { # loop over all users used in tests
            # Write-Output $user.UPN
            foreach ($app in $allApplications) { # loop over all applications used in tests
                # Write-Output "   $($app.applicationName)"

                # if all client apps are selected, then assign the common 3 client apps
                if ($conditionalAccessPolicy.conditions.clientAppTypes -eq "all") {
                    $conditionalAccessPolicy.conditions.clientAppTypes = @("browser", "mobileAppsAndDesktopClients", "other")
                }

                foreach ($clientApp in $conditionalAccessPolicy.conditions.clientAppTypes) { # loop over all clientApps of the policy
                    # Write-Output "   $($clientApp)"
                    
                    # Get all IP ranges. If the CA Policy does not use Named locations, an IP range with 'All' is returned. This 'empty' IP range is required to continue the foreach loop below.
                    [array]$allIPRanges = Get-IPRanges $conditionalAccessPolicy.conditions.locations.includeLocations $conditionalAccessPolicy.conditions.locations.excludeLocations
                                    
                    foreach ($ipRange in $allIPRanges) { # loop over IP ranges
                        # Transform the IP range to an IP address
                        $ipRange.IPrange = $ipRange.IPrange.Split("/")[0]

                        # Get all device platforms
                        [array]$alldevicePlatforms = Get-devicePlatforms $conditionalAccessPolicy.conditions.platforms.includePlatforms $conditionalAccessPolicy.conditions.platforms.excludePlatforms                    

                        foreach ($devicePlatform in $alldevicePlatforms) { # loop over IP ranges

                            [array]$allUserRisks = $conditionalAccessPolicy.conditions.userRiskLevels
                            
                            # if no user risk levels are set, then set 'all'. This will not be printed in the test itself
                            if (-Not $conditionalAccessPolicy.conditions.userRiskLevels) {
                                $conditionalAccessPolicy.conditions.userRiskLevels = @('All')
                            } 

                            foreach ($userRisk in $conditionalAccessPolicy.conditions.userRiskLevels) { # loop over user risks

                                [array]$allSignInRisks = $conditionalAccessPolicy.conditions.signInRiskLevels
                            
                                # if no user risk levels are set, then set 'all'. This will not be printed in the test itself
                                if (-Not $conditionalAccessPolicy.conditions.signInRiskLevels) {
                                    $conditionalAccessPolicy.conditions.signInRiskLevels = @('All') # TODO: do we set 'None' here as default? Then every test where SigninRisk is not configured, 'None' is added as signInRisk
                                } 

                                foreach ($signInRisk in $allSignInRisks) { # loop over signin risks

                                    [array]$userActions = $conditionalAccessPolicy.conditions?.authenticationFlows?.transferMethods -split ',' 

                                    if (-Not $conditionalAccessPolicy.conditions?.authenticationFlows?.transferMethods) {
                                        ($conditionalAccessPolicy.conditions ??= @{}).authenticationFlows = @{ transferMethods = @('All') } # Add the property 'transferMethods'
                                    }

                                    foreach ($userAction in $userActions) { # loop over userActions


                                        # if user or app or IP range is excluded, we invert the test to a -Not
                                        $invertedTest = $user.type -eq "excluded" -or $app.type -eq "excluded" -or $ipRange.type -eq "excluded" -or $devicePlatform.type -eq "excluded"
                                        
                                        if ($conditionalAccessPolicy.grantControls.builtInControls -contains "block") {
                                            $testName = Create-TestName $invertedTest 'block' $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $clientApp $ipRange.IPrange $devicePlatform.OS $userRisk $signInRisk $userAction
                                            $MaesterTests += Generate-MaesterTest $invertedTest 'block' $testName $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $clientApp $ipRange.IPrange $devicePlatform.OS $userRisk $signInRisk $userAction
                                            $testsCreatedForThisCAPolicy++
                                        }

                                        if ($conditionalAccessPolicy.grantControls.builtInControls -contains "mfa") { # TODO: I think that if the action is 'passwordChange', then 'mfa' is also given as an action. To check. And to check if me must leave this out then...
                                            $testName = Create-TestName $invertedTest 'mfa' $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $clientApp $ipRange.IPrange $devicePlatform.OS $userRisk $signInRisk $userAction
                                            $MaesterTests += Generate-MaesterTest $invertedTest 'mfa' $testName $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $clientApp $ipRange.IPrange $devicePlatform.OS $userRisk $signInRisk $userAction
                                            $testsCreatedForThisCAPolicy++
                                        }

                                        if ($conditionalAccessPolicy.grantControls.builtInControls -contains "passwordChange") { 
                                            $testName = Create-TestName $invertedTest 'passwordChange' $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $clientApp $ipRange.IPrange $devicePlatform.OS $userRisk $signInRisk $userAction
                                            $MaesterTests += Generate-MaesterTest $invertedTest 'passwordChange' $testName $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $clientApp $ipRange.IPrange $devicePlatform.OS $userRisk $signInRisk $userAction
                                            $testsCreatedForThisCAPolicy++
                                        }

                                        if ($conditionalAccessPolicy.grantControls.builtInControls -contains "compliantDevice") {
                                            $testName = Create-TestName $invertedTest 'compliantDevice' $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $clientApp $ipRange.IPrange $devicePlatform.OS $userRisk $signInRisk $userAction
                                            $MaesterTests += Generate-MaesterTest $invertedTest 'compliantDevice' $testName $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $clientApp $ipRange.IPrange $devicePlatform.OS $userRisk $signInRisk $userAction
                                            $testsCreatedForThisCAPolicy++
                                        }

                                        if ($conditionalAccessPolicy.grantControls.builtInControls -contains "domainJoinedDevice") {
                                            $testName = Create-TestName $invertedTest 'domainJoinedDevice' $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $clientApp $ipRange.IPrange $devicePlatform.OS $userRisk $signInRisk $userAction
                                            $MaesterTests += Generate-MaesterTest $invertedTest 'domainJoinedDevice' $testName $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $clientApp $ipRange.IPrange $devicePlatform.OS $userRisk $signInRisk $userAction
                                            $testsCreatedForThisCAPolicy++
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        $i++
        Write-OutputSuccess "$testsCreatedForThisCAPolicy tests generated for '$($conditionalAccessPolicy.displayName)' ($($conditionalAccessPolicy.id))"
        # break # Uncomment for debugging purposes
    }

    Write-OutputSuccess "Generated $($MaesterTests.count) Maester tests"
    # Write-Output $MaesterTests | ConvertTo-JSON

    return $MaesterTests
}