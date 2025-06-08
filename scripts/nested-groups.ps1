# Import shared.ps1
. ([System.IO.Path]::Combine($PSScriptRoot, 'shared.ps1'))

#################
# NESTED GROUPS #
#################
function Get-NestedGroups {
    param ()

    Write-OutputInfo "Generating nested group flow chart"

    # Get all groups with their transitive members
    $groupsWithMembers = Get-AllPagesFromMicrosoftGraph 'https://graph.microsoft.com/v1.0/groups?$expand=transitiveMembers'

    # Build a lookup for groupId -> group object
    $groupLookup = @{}
    foreach ($g in $groupsWithMembers) {
        $groupLookup[$g.id] = $g
    }

    # Find all parent group IDs (groups that have group members)
    $groupsWithMemberGroups = $groupsWithMembers | ForEach-Object {
        $_.transitiveMembers = $_.transitiveMembers | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.group' }
        $_
    } | Where-Object { $_.transitiveMembers.Count -gt 0 }
    $parentGroupIds = $groupsWithMemberGroups | Select-Object -ExpandProperty id

    # Find all child group IDs (groups that are members of other groups)
    $childGroupIds = $groupsWithMembers.transitiveMembers | ForEach-Object {
        $_ | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.group' }
    } | Select-Object -ExpandProperty id

    # Top-level groups: parent but not child
    $topLevelGroupIds = $parentGroupIds | Where-Object { $_ -notin $childGroupIds }
    $topLevelGroups = $groupsWithMembers | Where-Object { $_.id -in $topLevelGroupIds }

    # Recursive function to build the nested group tree
    function Build-NestedGroupTree {
        param (
            [string]$groupId
        )
        $group = $groupLookup[$groupId]
        if (-not $group -or -not $group.transitiveMembers) {
            return ""
        }
        $subGroups = $group.transitiveMembers | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.group' }
        if ($subGroups.Count -eq 0) {
            return ""
        }
        $result = @{}
        foreach ($subGroup in $subGroups) {
            $result[$subGroup.displayName] = Build-NestedGroupTree -groupId $subGroup.id
        }
        return $result
    }

    $nestedGroups = @{}
    foreach ($topGroup in $topLevelGroups) {
        $nestedGroups[$topGroup.displayName] = Build-NestedGroupTree -groupId $topGroup.id
    }

    return $nestedGroups
}
