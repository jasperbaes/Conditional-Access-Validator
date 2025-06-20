function Invoke-HuntingQuery {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Query
    )

    $response = Invoke-MgGraphRequest -Method POST 'https://graph.microsoft.com/v1.0/security/runHuntingQuery' -Body @{
        Query = $Query
    } -ContentType 'application/json'
    return $response
}

function Get-HuntingResults {
    # Define queries with Id and Query properties
    $queries = @(
        @{
            Id = "UniqueIPPerApp"
            Title = "Service Principals can be restricted to a single IP address"
            Description = "This check finds Entra Service Principals that use a single IP address for all sign-ins, excluding managed identities."
            Query = @'
AADSpnSignInEventsBeta | where TimeGenerated >= ago(30d) | where ErrorCode == 0 | where IsManagedIdentity == 0 | summarize UniqueIPCount = dcount(IPAddress) by ApplicationId | where UniqueIPCount == 1 | join kind=leftouter ( AADSpnSignInEventsBeta | summarize by ApplicationId, IPAddress, ServicePrincipalName) on $left.ApplicationId == $right.ApplicationId | project ['IP Address'] = IPAddress, ['Service Principal Name'] = ServicePrincipalName, ['Application ID'] = ApplicationId
'@
            Author = 'Jasper Baes'
            AuthorURL = 'https://www.linkedin.com/in/jasper-baes/'
        },
         @{
            Id = "changedCAPolicy"
            Title = "Changed Conditional Access Policies"
            Description = "This query detects changes to Conditional Access policies in the last 30 days, including modifications to policy settings and conditions."
            Query = @'
AuditLogs | where SourceSystem == "Azure AD" | where OperationName == "Update conditional access policy" | where Result  == "success" | extend ChangedCaPolicy = tostring(TargetResources[0].displayName) //check to optimise this line | extend Actor = tostring(parse_json(tostring(InitiatedBy.user)).userPrincipalName) | extend NewGeneralSettings = parse_json(tostring(parse_json(tostring(TargetResources[0].modifiedProperties))[0].newValue)) | extend OldGeneralSettings = parse_json(tostring(parse_json(tostring(TargetResources[0].modifiedProperties))[0].oldValue)) | extend NewConditions = parse_json(tostring(parse_json(tostring(parse_json(tostring(TargetResources[0].modifiedProperties))[0].newValue)).conditions)) | extend OldConditions = parse_json(tostring(parse_json(tostring(parse_json(tostring(TargetResources[0].modifiedProperties))[0].oldValue)).conditions)) | extend ChangedUser = iff(tostring(OldConditions.users) != tostring(NewConditions.users),  true , false) | extend ChangedApplications = iff(tostring(OldConditions.applications) != tostring(NewConditions.applications),  true , false) | order by TimeGenerated | extend  ChangedClientAppTypes= iff(tostring(OldConditions.clientAppTypes) != tostring(NewConditions.clientAppTypes), true ,false) | extend ChangedLocations= iff(tostring(OldConditions.locations) != tostring(NewConditions.locations), true , false) | order by TimeGenerated | extend ChangedPlatforms= iff(tostring(OldConditions.platforms) != tostring(NewConditions.platforms),  true , false) | extend ChangedServicePrincipalRiskLevels= iff(tostring(OldConditions.servicePrincipalRiskLevels) != tostring(NewConditions.servicePrincipalRiskLevels),  true , false) | extend ChangedSignInRiskLevels= iff(tostring(OldConditions.signInRiskLevels) != tostring(NewConditions.signInRiskLevels),  true , false) | extend ChangedUserRiskLevels= iff(tostring(OldConditions.userRiskLevels) != tostring(NewConditions.userRiskLevels),  true , false) | extend ChangedGrantControl = iff(tostring(OldGeneralSettings.grantControls) != tostring(NewGeneralSettings.grantControls),  true , false) | extend ChangedState = iff(tostring(OldGeneralSettings.state) != tostring(NewGeneralSettings.state),  true , false) | extend ChangedSessionControl = iff(tostring(OldGeneralSettings.sessionControls) != tostring(NewGeneralSettings.sessionControls),  true , false) | where ChangedUser or ChangedApplications or ChangedClientAppTypes or ChangedLocations or ChangedPlatforms or ChangedServicePrincipalRiskLevels or ChangedSignInRiskLevels or ChangedUserRiskLevels or ChangedGrantControl or ChangedState or ChangedSessionControl | project TimeGenerated, Actor, ChangedCaPolicy, ChangedUser, ChangedApplications, ChangedLocations, ChangedPlatforms, ChangedServicePrincipalRiskLevels, ChangedSignInRiskLevels, ChangedUserRiskLevels, ChangedGrantControl, ChangedState, ChangedSessionControl
'@
            Author = 'Louis Mastelinck'
            AuthorURL = 'https://www.lousec.be/ad/detect-security-policy-changes/'
        },
        @{
            Id = "SuspiciousCAChanges"
            Title = "Suspicious Conditional Access Policy Changes"
            Description = "This query detects suspicious changes to Conditional Access policies, such as removing users from includes, adding users to excludes, and other significant modifications. It also checks for PIM activations with justifications related to Conditional Access changes."
            Query = @'
let ca_include_naming_convention = "CA-Include"; let ca_exclude_naming_convention = "CA-Exclude"; let ca_pim_activations = AuditLogs | where TimeGenerated > ago(24h) | where OperationName contains "completed (PIM activation)" | parse AdditionalDetails with * "{\"key\":\"StartTime\",\"value\":\"" PimStartTime "\"" * "{\"key\":\"ExpirationTime\",\"value\":\"" PimExpirationTime "\"" * "{\"key\":\"Justification\",\"value\":\"" PimJustification "\"" * | where PimJustification has_any ("Conditional Access", "CA", "Trusted", "Named", "Location") | extend UserPrincipalName = tostring(InitiatedBy.user.userPrincipalName) | project OperationName, PimJustification, PimStartTime, PimExpirationTime, UserPrincipalName; let policy_changes = AuditLogs | where TimeGenerated > ago(24h) | where OperationName in ("Update conditional access policy", "Delete conditional access policy") | mv-expand TargetResources | mv-expand TargetResources.modifiedProperties | extend NewValueConditions = parse_json(tostring(parse_json(TargetResources_modifiedProperties.newValue))).conditions | extend OldValueConditions = parse_json(tostring(parse_json(TargetResources_modifiedProperties.oldValue))).conditions | extend NewValueGrandControls = parse_json(tostring(parse_json(TargetResources_modifiedProperties.newValue))).grantControls | extend OldValueGrandControls = parse_json(tostring(parse_json(TargetResources_modifiedProperties.oldValue))).grantControls | extend NewValueSessionControls = parse_json(tostring(parse_json(TargetResources_modifiedProperties.newValue))).sessionControls | extend OldValueSessionControls = parse_json(tostring(parse_json(TargetResources_modifiedProperties.oldValue))).sessionControls | extend NewState = parse_json(tostring(parse_json(TargetResources_modifiedProperties.newValue))).state | extend OldState = parse_json(tostring(parse_json(TargetResources_modifiedProperties.oldValue))).state | extend CountNewUserIncludes = array_length(NewValueConditions.users.includeUsers), CountNewRoleIncludes = array_length(NewValueConditions.users.includeRoles), CountNewGroupIncludes = array_length(NewValueConditions.users.includeGroups), CountNewUserActionIncludes = array_length(NewValueConditions.applications.inlcudeUserActions), CountNewAuthContextIncludes = array_length(NewValueConditions.applications.includeAuthenticationContextClassReferences), CountNewApplicationIncludes = array_length(NewValueConditions.applications.inlcudeApplications), CountNewLocationIncludes = array_length(NewValueConditions.locations.includeLocations), CountNewPlatformIncludes = array_length(NewValueConditions.platforms.includePlatforms) | extend CountOldUserIncludes = array_length(OldValueConditions.users.includeUsers), CountOldRoleIncludes = array_length(OldValueConditions.users.includeRoles), CountOldGroupIncludes = array_length(OldValueConditions.users.includeGroups), CountOldUserActionIncludes = array_length(OldValueConditions.applications.inlcudeUserActions), CountOldAuthContextIncludes = array_length(OldValueConditions.applications.includeAuthenticationContextClassReferences), CountOldApplicationIncludes = array_length(OldValueConditions.applications.inlcudeApplications), CountOldLocationIncludes = array_length(OldValueConditions.locations.includeLocations), CountOldPlatformIncludes = array_length(OldValueConditions.platforms.includePlatforms) | extend CountNewUserExcludes = array_length(NewValueConditions.users.excludeUsers), CountNewRoleExcludes = array_length(NewValueConditions.users.excludeRoles), CountNewGroupExcludes = array_length(NewValueConditions.users.excludeGroups), CountNewApplicationExcludes = array_length(NewValueConditions.applications.excludeApplications), CountNewLocationExcludes = array_length(NewValueConditions.locations.excludeLocations), CountNewPlatformExcludes = array_length(NewValueConditions.platforms.excludePlatforms) | extend CountOldUserExcludes = array_length(OldValueConditions.users.excludeUsers), CountOldRoleExcludes = array_length(OldValueConditions.users.excludeRoles), CountOldGroupExcludes = array_length(OldValueConditions.users.excludeGroups), CountOldApplicationExcludes = array_length(OldValueConditions.applications.excludeApplications), CountOldLocationExcludes = array_length(OldValueConditions.locations.excludeLocations), CountOldPlatformExcludes = array_length(OldValueConditions.platforms.excludePlatforms) | extend Reasons = dynamic([]) | extend Reasons = iff(CountNewUserIncludes < CountOldUserIncludes, array_concat(Reasons, dynamic(["User removed from include"])), Reasons) | extend Reasons = iff(CountNewRoleIncludes < CountOldRoleIncludes, array_concat(Reasons, dynamic(["Role removed from include"])), Reasons) | extend Reasons = iff(CountNewGroupIncludes < CountOldGroupIncludes, array_concat(Reasons, dynamic(["Group removed from include"])), Reasons) | extend Reasons = iff(CountNewUserExcludes > CountOldUserExcludes, array_concat(Reasons, dynamic(["User added to exclude"])), Reasons) | extend Reasons = iff(CountNewRoleExcludes > CountOldRoleExcludes, array_concat(Reasons, dynamic(["Role added to exclude"])), Reasons) | extend Reasons = iff(CountNewGroupExcludes > CountOldGroupExcludes, array_concat(Reasons, dynamic(["Group added to exclude"])), Reasons) | extend Reasons = iff(CountNewUserActionIncludes < CountOldUserActionIncludes, array_concat(Reasons, dynamic(["User action removed from include"])), Reasons) | extend Reasons = iff(CountNewAuthContextIncludes < CountOldAuthContextIncludes, array_concat(Reasons, dynamic(["Authentication context removed from include"])), Reasons) | extend Reasons = iff(CountNewApplicationIncludes < CountOldApplicationIncludes, array_concat(Reasons, dynamic(["Application removed from include"])), Reasons) | extend Reasons = iff(CountNewApplicationExcludes > CountOldApplicationExcludes, array_concat(Reasons, dynamic(["Application added to exclude"])), Reasons) | extend Reasons = iff(CountNewLocationIncludes < CountOldLocationIncludes, array_concat(Reasons, dynamic(["Locations removed from include"])), Reasons) | extend Reasons = iff(CountNewLocationExcludes > CountOldLocationExcludes, array_concat(Reasons, dynamic(["Locations added to exclude"])), Reasons) | extend Reasons = iff(CountNewPlatformIncludes < CountOldPlatformIncludes, array_concat(Reasons, dynamic(["Platforms removed from include"])), Reasons) | extend Reasons = iff(CountNewPlatformExcludes > CountOldPlatformExcludes, array_concat(Reasons, dynamic(["Platforms added to exclude"])), Reasons) | extend Reasons = iff(tostring(NewValueConditions.applications.applicationFilter) != tostring(OldValueConditions.applications.applicationFilter), array_concat(Reasons, dynamic(["Application filter changed"])), Reasons) | extend Reasons = iff(tostring(NewValueConditions.clientAppTypes) != tostring(OldValueConditions.clientAppTypes), array_concat(Reasons, dynamic(["Client app type changed"])), Reasons) | extend Reasons = iff(tostring(NewValueConditions.userRiskLevels) != tostring(OldValueConditions.userRiskLevels), array_concat(Reasons, dynamic(["User risk levels changed"])), Reasons) | extend Reasons = iff(tostring(NewValueConditions.signInRiskLevels) != tostring(OldValueConditions.signInRiskLevels), array_concat(Reasons, dynamic(["Sign-in risk levels changed"])), Reasons) | extend Reasons = iff(tostring(NewValueConditions.servicePrincipalRiskLevels) != tostring(OldValueConditions.servicePrincipalRiskLevels), array_concat(Reasons, dynamic(["Service Principal risk levels changed"])), Reasons) | extend Reasons = iff(tostring(NewValueGrandControls) != tostring(OldValueGrandControls), array_concat(Reasons, dynamic(["Grant controls changed"])), Reasons) | extend Reasons = iff(tostring(NewValueSessionControls) != tostring(OldValueSessionControls), array_concat(Reasons, dynamic(["Session controls changed"])), Reasons) | extend Reasons = iff(tostring(NewValueConditions.devices) != tostring(OldValueConditions.devices), array_concat(Reasons, dynamic(["Device conditions changed"])), Reasons) | extend Reasons = iff(tostring(OldValueConditions.locations.includeLocations) contains "all" and tostring(NewValueConditions.locations.includeLocations) !contains "all", array_concat(Reasons, dynamic(["Include locations changed from all to specific"])), Reasons) | extend Reasons = iff(tostring(OldValueConditions.platforms.includePlatforms) contains "all" and tostring(NewValueConditions.platforms.includePlatforms) !contains "all", array_concat(Reasons, dynamic(["Include platforms changed from all to specific"])), Reasons) | extend Reasons = iff(tostring(OldValueConditions.users.includeUsers) contains "all" and tostring(NewValueConditions.users.includeUsers) !contains "all", array_concat(Reasons, dynamic(["Include users changed from all to specific"])), Reasons) | extend Reasons = iff(tostring(OldValueConditions.applications.includeApplications) contains "all" and tostring(NewValueConditions.applications.includeApplications) !contains "all", array_concat(Reasons, dynamic(["Include applications changed from all to specific"])), Reasons) | extend Reasons = iff(tostring(OldState) == "enabled" and tostring(NewState) != "enabled", array_concat(Reasons, dynamic(["Policy was disabled"])), Reasons) | extend Reasons = iff(OperationName == "Delete conditional access policy", array_concat(Reasons, dynamic(["Policy was deleted"])), Reasons); let named_locations = AuditLogs | where TimeGenerated > ago(24h) | where OperationName in ("Add named location", "Update named location") | mv-expand TargetResources | mv-expand TargetResources.modifiedProperties | extend NewValueIsTrusted = parse_json(tostring(parse_json(TargetResources_modifiedProperties.newValue))).isTrusted | where NewValueIsTrusted == "true" | extend Reasons = dynamic([]) | extend Reasons = iff(OperationName == "Add named location", array_concat(Reasons, dynamic(["Trusted named location was added"])), Reasons) | extend Reasons = iff(OperationName == "Update named location", array_concat(Reasons, dynamic(["Trusted named location was updated"])), Reasons); let remove_from_include_group = AuditLogs | where TimeGenerated > ago(24h) | where OperationName == "Remove member from group" | mv-expand TargetResources | mv-expand TargetResources.modifiedProperties | where TargetResources_modifiedProperties.displayName == "Group.DisplayName" and TargetResources_modifiedProperties contains ca_include_naming_convention | extend Reasons = dynamic([]) | extend Reasons = dynamic(["Member removed from include group used in CA policy"]); let add_to_exclude_group = AuditLogs | where TimeGenerated > ago(24h) | where OperationName == "Add member to group" | mv-expand TargetResources | mv-expand TargetResources.modifiedProperties | where TargetResources_modifiedProperties.displayName == "Group.DisplayName" and TargetResources_modifiedProperties contains ca_exclude_naming_convention | extend Reasons = dynamic([]) | extend Reasons = dynamic(["Member added to exclude group used in CA policy"]); union policy_changes, named_locations, remove_from_include_group, add_to_exclude_group | where Reasons != "[]" | sort by TimeGenerated desc | project TimeGenerated, OperationName, InitiatedBy, LoggedByService, Result, TargetResources, AADOperationType, Reasons | extend UserPrincipalName = tostring(InitiatedBy.user.userPrincipalName) | join kind=leftouter ca_pim_activations on UserPrincipalName | project-away UserPrincipalName1 | extend JustifiedPIM = iff(isnotempty(PimStartTime) and isnotempty(PimExpirationTime) and TimeGenerated between (todatetime(PimStartTime) .. todatetime(PimExpirationTime)), true, false) | where JustifiedPIM == false
'@
            Author = 'Robbe Van den Daele'
            AuthorURL = 'https://www.linkedin.com/in/robbe-van-den-daele-677986190/'
            QueryURL = 'https://github.com/HybridBrothers/Hunting-Queries-Detection-Rules/blob/main/Entra%20ID/DetectSuspiciousCaChanges.md'
        },
        @{
            Id = "createdCAPolicy"
            Title = "New Conditional Access Policies created"
            Description = "This query detects the creation of new Conditional Access policies in the last 30 days."
            Query = @'
AuditLogs | where TimeGenerated >= ago(30d) | where SourceSystem == "Azure AD" | where OperationName == "Add conditional access policy" | where Result == "success" | extend Actor = InitiatedBy.user.userPrincipalName | extend CreatedCAPolicy = TargetResources[0].displayName | extend CAPolicySettings = TargetResources[0].modifiedProperties[0].newValue | project TimeGenerated, Actor, CreatedCAPolicy, CAPolicySettings
'@
            Author = 'Louis Mastelinck'
            AuthorURL = 'https://www.lousec.be/ad/detect-security-policy-changes/'
        },
        @{
            Id = "deletedCAPolicy"
            Title = "Deleted Conditional Access Policies"
            Description = "This query detects the deletion of Conditional Access policies in the last 30 days."
            Query = @'
AuditLogs | where TimeGenerated >= ago(30d) | where SourceSystem == "Azure AD" | where OperationName == "Delete conditional access policy" | where Result == "success" | extend Actor = InitiatedBy.user.userPrincipalName | extend DeletedCAPolicy = TargetResources[0].displayName | extend CAPolicySettings = TargetResources[0].modifiedProperties[0].oldValue | project TimeGenerated, Actor, DeletedCAPolicy, CAPolicySettings
'@
            Author = 'Louis Mastelinck'
            AuthorURL = 'https://www.lousec.be/ad/detect-security-policy-changes/'
        },
        @{
            Id = "browserUsage"
            Title = "Browsers used"
            Description = "This query provides a summary of the browsers used in successful sign-ins over the last 30 days, excluding errors and empty user agents. It parses the user agent string to extract browser information."
            Query = @'
AADSignInEventsBeta | where TimeGenerated >= ago(30d) | where isnotempty(UserAgent) | where ErrorCode == 0 | extend ParsedAgent = parse_json(parse_user_agent(UserAgent, "browser")) | extend Browser = strcat(tostring(ParsedAgent.Browser.Family), " ", tostring(ParsedAgent.Browser.MajorVersion), ".", tostring(ParsedAgent.Browser.MinorVersion)) | summarize Total = count() by Browser | sort by Total
'@
            Author = 'Bert-Jan Pals'
            AuthorURL = 'https://github.com/Bert-JanP/Hunting-Queries-Detection-Rules/blob/main/Azure%20Active%20Directory/SignInsByBrowser.md'
        }
    )

    $resultsTable = @()

    foreach ($q in $queries) {
        $result = Invoke-HuntingQuery -Query $q.Query

        # Convert each hashtable in the result to a PSCustomObject
        $typedResults = @()
        foreach ($item in $result.results) {
            $typedResults += [PSCustomObject]$item
        }

        $resultsTable += [PSCustomObject]@{
            Id = $q.Id
            Title = $q.Title
            Description = $q.Description
            ResultAmount = $typedResults.Count
            Result = $typedResults
            Author = $q.Author
            AuthorURL = $q.AuthorURL
            QueryURL = $q.QueryURL
        }
    }

    return $resultsTable
}