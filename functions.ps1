function Write-OutputError { param ( [string]$Message ) Write-Host " [" -ForegroundColor White -NoNewline; Write-Host "-" -ForegroundColor Red -NoNewline; Write-Host "] $Message" -ForegroundColor White }
function Write-OutputSuccess { param ( [string]$Message ) Write-Host " [" -ForegroundColor White -NoNewline; Write-Host "+" -ForegroundColor Green -NoNewline; Write-Host "] $Message" -ForegroundColor White }
function Write-OutputInfo { param ( [string]$Message ) Write-Host " [" -ForegroundColor White -NoNewline; Write-Host "i" -ForegroundColor Blue -NoNewline; Write-Host "] $Message" -ForegroundColor White }


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
                $allApplications += @{
                    applicationID = $appID
                    applicationName = Get-AppNamebyID $appID
                    type = "included"
                }
                $addedCount++
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
                $allApplications += @{
                    applicationID = $appID
                    applicationName = Get-AppNamebyID $appID
                    type = "excluded"
                }
                $addedCount++
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
        $userRisk
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


# This function returns ...
function Get-devicePlatforms {
    param (
        $includedDevicePlatforms,
        $excludedDevicePlatforms
    ) 
    
    $allPlatforms = @() # create empty array

    # if the CA policy has no included or excluded location set, then create an 'empty' IP range. This will not be added to the test itself. This object is required so it continues in the nested forEach loop
    if ($includedDevicePlatforms.count -eq 0 -or $excludedDevicePlatforms.count -eq 0) {
        $allPlatforms += @{
            OS = 'All'
            type = "included" # it does not matter if this is 'included' or 'excluded'. We will filter these out when generating the Maester test code
        }
    }

    # Loop over all includedDevicePlatforms
    foreach ($devicePlatform in $includedDevicePlatforms) {
        $allPlatforms += @{
            OS = $devicePlatform
            type = "included"
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
        $userRisk
    )

    $testTitle = "$expectedControl for $UPN on $appName"

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

    return $testTitle
}

##############
# JSON CRACK #
##############


function Get-ConditionalAccessFlowChart  {
    param (
        $MaesterTests
    )

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


######################
# User Impact Matrix #
######################

function Get-UserImpactMatrix {
    param (
        $conditionalAccessPolicies
    )

    Write-OutputInfo "Generating User Impact Matrix. This can take a while"
    
    $userImpactMatrix = @()

    $users = Get-AllPagesFromMicrosoftGraph 'https://graph.microsoft.com/v1.0/users?$select=userPrincipalName,displayName,jobTitle,id,accountEnabled,userType'

    Write-OutputInfo "$($users.count) users found"

    foreach ($user in $users) {
        $groupList = (Invoke-MgGraphRequest -Method GET ('https://graph.microsoft.com/v1.0/users/' + $user.id + '/memberOf?$select=id')).value.id

        $userObject = [ordered]@{
            user = $user.displayname -replace '[,;]', ''
            upn = $user.userPrincipalName -replace '[,;]', ''
            job = $user.jobTitle -replace '[,;]', ''
            external = $user.userPrincipalName -like '*#EXT#@*'
            enabled =$user.accountEnabled
        }

        foreach ($policy in $conditionalAccessPolicies) {
            $userObject[$policy.displayName] = Get-userIncludedInCAPolicy $policy $user $groupList
        }

        $userImpactMatrix += $userObject
    }

    return $userImpactMatrix
}

function Get-userIncludedInCAPolicy {
    param (
        $policy,
        $user,
        $groupList
    )

    if ($policy.conditions.users.excludeUsers -contains $user.id) {
        return $false
    }

    if ($policy.conditions.users.excludeGroups.count -ge 1) {
        $excludedGroupsRecursive = Get-SubgroupsRecursive $policy.conditions.users.excludeGroups
        if ((Check-Arrays $groupList $excludedGroupsRecursive) -eq $true) {
            return $false
        }
    }

    if ($policy.conditions.users.includeUsers -contains 'All') { 
        return $true
    }

    if ($policy.conditions.users.includeUsers -contains $user.id) {
        return $true
    }

    if ($policy.conditions.users.includeGroups.count -ge 1) {
        $includedGroupsRecursive = Get-SubgroupsRecursive $policy.conditions.users.includeGroups
        
        if ((Check-Arrays $groupList $includedGroupsRecursive) -eq $true) {
            return $true
        }
    }

    return $false
}

function Get-SubgroupsRecursive {
    param (
        $groups
    )

    $allgroupIDs = @()

    foreach ($group1 in $groups) {
        $allgroupIDs += $group1
        $groupList = (Invoke-MgGraphRequest -Method GET ('https://graph.microsoft.com/v1.0/groups/' + $group1 + '/transitiveMembers?$select=id')).value

        foreach ($group2 in $groupList) {
            if ($group2['@odata.type'] -eq '#microsoft.graph.group') {
                Get-SubgroupsRecursive $group2.id
            }
        }
    }

    return $allgroupIDs
}

function Check-Arrays {
    param (
        [array]$arr1,
        [array]$arr2
    )

    foreach ($item in $arr1) {
        if ($arr2 -contains $item) {
            return $true
        }
    }

    foreach ($item in $arr2) {
        if ($arr1 -contains $item) {
            return $true
        }
    }

    return $false
}

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