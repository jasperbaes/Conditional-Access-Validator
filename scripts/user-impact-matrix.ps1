# Import shared.ps1
. ([System.IO.Path]::Combine($PSScriptRoot, 'shared.ps1'))

######################
# User Impact Matrix #
######################

function Get-UserImpactMatrix {
    param (
        $conditionalAccessPolicies,
        $UserImpactMatrixLimit
    )

    Write-OutputInfo "Generating User Impact Matrix. This can take a while"
    
    $userImpactMatrix = @()

    $users = Get-AllPagesFromMicrosoftGraph 'https://graph.microsoft.com/v1.0/users?$select=userPrincipalName,displayName,jobTitle,id,accountEnabled,userType'

    Write-OutputInfo "$($users.count) users found"

    if ($UserImpactMatrixLimit -and $UserImpactMatrixLimit -gt 0) {
        Write-OutputInfo "Limiting to the first $($UserImpactMatrixLimit) users"
        $users = $users | Select-Object -First $UserImpactMatrixLimit
    }
    
    $i = 0

    foreach ($user in $users) {
        $percentComplete = [math]::Round(($i / $users.Count) * 100)
        Write-Progress -Activity "     Generating CA User Impact Matrix..." -Status "$percentComplete% Complete" -PercentComplete $percentComplete

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

        $i++
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