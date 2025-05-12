# Import shared.ps1
. ([System.IO.Path]::Combine($PSScriptRoot, 'shared.ps1'))

#################
# NESTED GROUPS #
#################
function Get-NestedGroups {
    param ()

    Write-OutputInfo "Generating nested group flow chart"

    $nestedGroups = @{}

    # Get groups with members
    $groupsWithMembers = Get-AllPagesFromMicrosoftGraph 'https://graph.microsoft.com/v1.0/groups?$expand=transitiveMembers'
    $groupsWithMemberGroups = $groupsWithMembers | ForEach-Object {
        $_.transitiveMembers = $_.transitiveMembers | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.group' }
        $_
    } | Where-Object { $_.transitiveMembers.Count -gt 0 }

    # Get all parent group IDs
    $parentGroupIds = $groupsWithMemberGroups | Select-Object -ExpandProperty id

    # Get all child group IDs
    $childGroupIds = $groupsWithMembers.transitiveMembers | ForEach-Object {
        $_ | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.group' }
    } | Select-Object -ExpandProperty id

    # Find top-level groups (only in parent list, not in child list)
    $topLevelGroupIds = $parentGroupIds | Where-Object { $_ -notin $childGroupIds }

    # Get full group objects for these IDs
    $topLevelGroups = $groupsWithMembers | Where-Object { $_.id -in $topLevelGroupIds } | Select displayName, id, transitiveMembers

    $nestedGroups = [ordered]@{}
    foreach ($topLevelGroup in $topLevelGroups) {
        $childGroups = Get-ChildGroups $topLevelGroup.id
        foreach ($key in $tree.Keys) {
            if ($null -ne $key -and -not ($nestedGroups.Keys -contains $key)) {
                $nestedGroups[$key] = $tree[$key]
            }
        }
    }

    exit

    function Get-ChildGroups {
        param (
            [string]$groupId
        )
    
        if ($visited.ContainsKey($groupId)) {
            return $null  # Prevent circular references
        }
        $visited[$groupId] = $true
    
        $group = $groupLookup[$groupId]
        $childGroups = $group.transitiveMembers | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.group' }
    
        # If no child groups, return just the name
        if (-not $childGroups -or $childGroups.Count -eq 0) {
            return $group.displayName
        }
    
        # Otherwise, build children recursively
        $children = [ordered]@{}
        foreach ($member in $childGroups) {
            $childTree = Build-NestedGroupTree -groupId $member.id -visited ($visited.Clone())
            if ($childTree -is [string]) {
                $children[$childTree] = ""
            } elseif ($childTree -is [hashtable]) {
                foreach ($k in $childTree.Keys) {
                    $children[$k] = $childTree[$k]
                }
            }
        }
    
        return [ordered]@{ $group.displayName = $children }
    }
    
    

    # Build the full tree starting from top-level groups
    $nestedGroups = [ordered]@{}
    foreach ($topLevelGroup in $topLevelGroups) {
        $tree = Build-NestedGroupTree -groupId $topLevelGroup.id
        foreach ($key in $tree.Keys) {
            if ($null -ne $key -and -not ($nestedGroups.Keys -contains $key)) {
                $nestedGroups[$key] = $tree[$key]
            }
        }
    }

    # Output the nested structure
    Write-Host ($nestedGroups | ConvertTo-Json -Depth 99)
    # return $nestedGroups
}
