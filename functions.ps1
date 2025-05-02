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
        [array]$randomUsers = @() # create empty array

        if ($scope -eq 'tenant') {
            $users = Invoke-MgGraphRequest -Method GET ('https://graph.microsoft.com/v1.0/users?$select=id,userPrincipalName')
            $usersList = $users.value
        } else { # scope is a groupID
            $users = Invoke-MgGraphRequest -Method GET ('https://graph.microsoft.com/v1.0/groups/' + $scope + '?$select=id,displayName&$expand=members')
            $usersList = $users.members
        }
        
        if ($usersList.Count -ge 5) {
            $randomUsersList = $usersList | Get-Random -Count 5   
        } else {
            $randomUsersList = $usersList 
        }

        # TODO: checken ofdat deze users niet in $excludeUsers of $excludeGroups zitten
        # TODO: changen ofdat er geen duplicaten zitten tussen de randoms

        foreach ($randomUser in $randomUsersList) {
            $randomUsers += @{
                userID = $randomUser.id
                UPN = $randomUser.userPrincipalName
            }
        }

        return $randomUsers
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

    if ($includeApplications -contains "All" -or $includeApplications -contains "Office365") { # add 3 default application if the policy is scoped to 'All' or 'Office365'
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

    if ($excludeApplications -contains "All" -or $excludeApplications -contains "Office365") { # add 3 default application if the policy is scoped to 'All' or 'Office365
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

    foreach ($appID in $includeApplications) { 
        if ($appID -ne "All" -and $appID -ne "Office365") {
            $allApplications += @{
                applicationID = $appID
                applicationName = Get-AppNamebyID $appID
                type = "included"
            }
        }
    }

    foreach ($appID in $excludeApplications) { 
        if ($appID -ne "All" -and $appID -ne "Office365") {
            $allApplications += @{
                applicationID = $appID
                applicationName = Get-AppNamebyID $appID
                type = "excluded"
            }
        }
    }

    # todo: max 3

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