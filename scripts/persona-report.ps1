# Import shared.ps1
. ([System.IO.Path]::Combine($PSScriptRoot, 'shared.ps1'))

##################
# Persona Report #
##################

# Add a global group cache
$global:GroupInfoCache = @{}

function Get-GroupNameAndCount {
    param (
        [string]$groupID,
        [hashtable]$groupCache = $null
    )
    if (-not $groupCache) { $groupCache = $global:GroupInfoCache }
    if ($groupCache.ContainsKey($groupID)) {
        return $groupCache[$groupID]
    }
    $group = Invoke-MgGraphRequest -Method GET ('https://graph.microsoft.com/v1.0/groups/' + $groupID + '?$select=displayName&$expand=members')
    $result = @{
        groupName = $group.displayName
        memberCount = $group.members.count
    }
    $groupCache[$groupID] = $result
    return $result
}

function Get-PersonaReport {
    param (
        $conditionalAccessPolicies
    )
    
    $resultsObject = @()
    $i = 1

    # Use a local cache for this run
    $groupCache = @{}

    # Loop over all discovered Conditional Access Policies
    foreach ($conditionalAccessPolicy in $conditionalAccessPolicies) {
        $percentComplete = [math]::Round(($i / $conditionalAccessPolicies.Count) * 100)
        Write-Progress -Activity "     Generating Persona Report..." -Status "$percentComplete% Complete" -PercentComplete $percentComplete

        $policyName = $conditionalAccessPolicy.displayName
        $policyID = $conditionalAccessPolicy.id
        $policyState = $conditionalAccessPolicy.state
        $policyIncludedGroups = $conditionalAccessPolicy.conditions.users.includeGroups
        $policyExcludedGroups = $conditionalAccessPolicy.conditions.users.excludeGroups

        $conditionalAccessPolicyResultsObject = @{}
        $conditionalAccessPolicyResultsObject.policyName = $policyName # set policy name
        $conditionalAccessPolicyResultsObject.policyID = $policyID # set policy ID
        $conditionalAccessPolicyResultsObject.policyState = if ($policyState -eq 'enabledForReportingButNotEnforced') {'report-only'} else {$policyState} # set policy state
        $conditionalAccessPolicyResultsObject.controls =  $conditionalAccessPolicy.grantControls.builtInControls # set controls
        
        # Parse included groups
        $conditionalAccessPolicyResultsObject.includedGroups = @() # create empty array

        if ($policyIncludedGroups) {
            foreach ($policyIncludedGroup in $policyIncludedGroups) { # loop over groups
                $groupResults = Get-GroupNameAndCount $policyIncludedGroup $groupCache # get group name and member count
                
                $conditionalAccessPolicyResultsObject.includedGroups += @{ # add object to array
                    groupID = $policyIncludedGroup
                    groupName = $groupResults.groupName
                    memberCount = $groupResults.memberCount
                }
            }
        }

        # Parse excluded groups
        $conditionalAccessPolicyResultsObject.excludedGroups = @() # create empty array

        if ($policyExcludedGroups) {
            foreach ($policyExcludedGroup in $policyExcludedGroups) { # loop over groups
                $groupResults = Get-GroupNameAndCount $policyExcludedGroup $groupCache # get group name and member count
                
                $conditionalAccessPolicyResultsObject.excludedGroups += @{ # add object to array
                    groupID = $policyExcludedGroup
                    groupName = $groupResults.groupName
                    memberCount = $groupResults.memberCount
                }
            }
        }

        $resultsObject += $conditionalAccessPolicyResultsObject
        $i++
    }

    return $resultsObject
}