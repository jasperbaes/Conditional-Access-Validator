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
AuditLogs | where SourceSystem == "Azure AD" | where OperationName == "Update conditional access policy" | where Result  == "success" | extend ChangedCaPolicy = tostring(TargetResources[0].displayName) //check to optimise this line | extend Actor = tostring(parse_json(tostring(InitiatedBy.user)).userPrincipalName) | extend NewGeneralSettings = parse_json(tostring(parse_json(tostring(TargetResources[0].modifiedProperties))[0].newValue)) | extend OldGeneralSettings = parse_json(tostring(parse_json(tostring(TargetResources[0].modifiedProperties))[0].oldValue)) | extend NewConditions = parse_json(tostring(parse_json(tostring(parse_json(tostring(TargetResources[0].modifiedProperties))[0].newValue)).conditions)) | extend OldConditions = parse_json(tostring(parse_json(tostring(parse_json(tostring(TargetResources[0].modifiedProperties))[0].oldValue)).conditions)) | extend ChangedUser = iff(tostring(OldConditions.users) != tostring(NewConditions.users),  true , false) | extend ChangedApplications = iff(tostring(OldConditions.applications) != tostring(NewConditions.applications),  true , false) | order by TimeGenerated | extend  ChangedClientAppTypes= iff(tostring(OldConditions.clientAppTypes) != tostring(NewConditions.clientAppTypes), true ,false) | extend ChangedLocations= iff(tostring(OldConditions.locations) != tostring(NewConditions.locations), true , false) | order by TimeGenerated | extend ChangedPlatforms= iff(tostring(OldConditions.platforms) != tostring(NewConditions.platforms),  true , false) | extend ChangedServicePrincipalRiskLevels= iff(tostring(OldConditions.servicePrincipalRiskLevels) != tostring(NewConditions.servicePrincipalRiskLevels),  true , false) | extend ChangedSignInRiskLevels= iff(tostring(OldConditions.signInRiskLevels) != tostring(NewConditions.signInRiskLevels),  true , false) | extend ChangedUserRiskLevels= iff(tostring(OldConditions.userRiskLevels) != tostring(NewConditions.userRiskLevels),  true , false) | extend ChangedGrantControl = iff(tostring(OldGeneralSettings.grantControls) != tostring(NewGeneralSettings.grantControls),  true , false) | extend ChangedState = iff(tostring(OldGeneralSettings.state) != tostring(NewGeneralSettings.state),  true , false) | extend ChangedSessionControl = iff(tostring(OldGeneralSettings.sessionControls) != tostring(NewGeneralSettings.sessionControls),  true , false) | where ChangedUser or ChangedApplications or ChangedClientAppTypes or ChangedLocations or ChangedPlatforms or ChangedServicePrincipalRiskLevels or ChangedSignInRiskLevels or ChangedUserRiskLevels or ChangedGrantControl or ChangedState or ChangedSessionControl | project ['Datetime'] = TimeGenerated, Actor, ChangedCaPolicy, ChangedUser, ChangedApplications, ChangedLocations, ChangedPlatforms, ChangedServicePrincipalRiskLevels, ChangedSignInRiskLevels, ChangedUserRiskLevels, ChangedGrantControl, ChangedState, ChangedSessionControl
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
AuditLogs | where TimeGenerated >= ago(30d) | where SourceSystem == "Azure AD" | where OperationName == "Add conditional access policy" | where Result == "success" | extend Actor = InitiatedBy.user.userPrincipalName | extend CreatedCAPolicy = TargetResources[0].displayName | extend CAPolicySettings = TargetResources[0].modifiedProperties[0].newValue | project ['Datetime'] = TimeGenerated, Actor, ['Created CA Policy'] = CreatedCAPolicy, ['CA Policy'] = CAPolicySettings
'@
            Author = 'Louis Mastelinck'
            AuthorURL = 'https://www.lousec.be/ad/detect-security-policy-changes/'
        },
        @{
            Id = "deletedCAPolicy"
            Title = "Deleted Conditional Access Policies"
            Description = "This query detects the deletion of Conditional Access policies in the last 30 days."
            Query = @'
AuditLogs | where TimeGenerated >= ago(30d) | where SourceSystem == "Azure AD" | where OperationName == "Delete conditional access policy" | where Result == "success" | extend Actor = InitiatedBy.user.userPrincipalName | extend DeletedCAPolicy = TargetResources[0].displayName | extend CAPolicySettings = TargetResources[0].modifiedProperties[0].oldValue | project ['Datetime'] = TimeGenerated, Actor, ['Deleted CA Policy'] = DeletedCAPolicy, ['CA Policy'] = CAPolicySettings
'@
            Author = 'Louis Mastelinck'
            AuthorURL = 'https://www.lousec.be/ad/detect-security-policy-changes/'
        },
        @{
            Id = "browserUsage"
            Title = "Browsers used"
            Description = "This query provides a summary of the browsers used in successful sign-ins over the last 30 days, excluding errors and empty user agents. It parses the user agent string to extract browser information."
            Query = @'
AADSignInEventsBeta | where TimeGenerated >= ago(30d) | where isnotempty(UserAgent) | where ErrorCode == 0 | extend ParsedAgent = parse_json(parse_user_agent(UserAgent, "browser")) | extend Browser = tostring(ParsedAgent.Browser.Family) | extend Browser = replace_string(Browser, "%20", " ") | summarize ['Total Sign-Ins'] = count() by Browser | sort by ['Total Sign-Ins'] desc
'@
            Author = 'Jasper Baes'
            AuthorURL = 'https://www.linkedin.com/in/jasper-baes/'
        },
        @{
            Id = "browserUsage"
            Title = "Browsers and versions used"
            Description = "This query provides a summary of the browsers and versions used in successful sign-ins over the last 30 days, excluding errors and empty user agents. It parses the user agent string to extract browser information."
            Query = @'
AADSignInEventsBeta | where TimeGenerated >= ago(30d) | where isnotempty(UserAgent) | where ErrorCode == 0 | extend ParsedAgent = parse_json(parse_user_agent(UserAgent, "browser")) | extend Browser = strcat(tostring(ParsedAgent.Browser.Family), " ", tostring(ParsedAgent.Browser.MajorVersion), ".", tostring(ParsedAgent.Browser.MinorVersion)) | summarize Total = count() by Browser | sort by Total | project ['Browser'] = Browser, ['Total Sign-Ins'] = Total
'@
            Author = 'Bert-Jan Pals'
            AuthorURL = 'https://github.com/Bert-JanP/Hunting-Queries-Detection-Rules/blob/main/Azure%20Active%20Directory/SignInsByBrowser.md'
        },
        @{
            Id = "InteractiveLegacyAuth"
            Title = "Interactive sign-ins using legacy authentication"
            Description = "This query identifies sign-ins using legacy authentication protocols, which are considered less secure. It filters sign-ins that do not use modern authentication methods and summarizes the results by application."
            Query = @'
SigninLogs | extend IsLegacyAuth = case(ClientAppUsed contains "Browser", "No", ClientAppUsed contains "Mobile Apps and Desktop clients", "No", ClientAppUsed contains "Exchange ActiveSync", "No", ClientAppUsed contains "Authenticated SMTP", "Yes", ClientAppUsed contains "Other clients", "Yes", "Unknown") | where IsLegacyAuth == 'Yes' | where ResultType == 0
'@
            Author = 'Alex Verboon'
            AuthorURL = 'https://github.com/alexverboon/Hunting-Queries-Detection-Rules/blob/main/Azure%20Active%20Directory/AzureAD-BasicAuth.md'
        },
        @{
            Id = "allLegacyAuth"
            Title = "Interactive and noninteractive sign-ins using legacy authentication"
            Description = "This query identifies both interactive and noninteractive sign-ins using legacy authentication protocols, which are considered less secure. It filters sign-ins that do not use modern authentication methods and summarizes the results by application."
            Query = @'
union  isfuzzy=true SigninLogs, AADNonInteractiveUserSignInLogs | extend IsLegacyAuth = case(ClientAppUsed contains "Browser", "No", ClientAppUsed contains "Mobile Apps and Desktop clients", "No", ClientAppUsed contains "Exchange ActiveSync", "No", ClientAppUsed contains "Authenticated SMTP", "Yes", ClientAppUsed contains "Other clients", "Yes", "Unknown") | where IsLegacyAuth == 'Yes' | where ResultType == 0
'@
            Author = 'Alex Verboon'
            AuthorURL = 'https://github.com/alexverboon/Hunting-Queries-Detection-Rules/blob/main/Azure%20Active%20Directory/AzureAD-BasicAuth.md'
        },
        @{
            Id = "FociTokenLogins"
            Title = "Logins using FOCI tokens (Family of Client IDs tokens)"
            Description = "This KQL query detects suspicious use of FOCI tokens by identifying sessions where a benign app (e.g., Teams) is followed by access to a high-risk app (e.g., Azure CLI) using a shared refresh token. The v2 version of this query enhances detection by flagging scope changes within the same app (e.g., RoadTools usage) and offers filters to reduce false positives."
            Query = @'
let maxTimeDiff = 90; let FociClientApplications = toscalar(externaldata(client_id: string) [@"https://raw.githubusercontent.com/secureworks/family-of-client-ids-research/refs/heads/main/known-foci-clients.csv"] with (format="csv", ignoreFirstRecord=true) | summarize FociClientId = make_list(client_id) ); let FociTokenRequest = materialize ( AADNonInteractiveUserSignInLogs | where TimeGenerated > ago(6h) | where HomeTenantId == ResourceTenantId | where AppId in (FociClientApplications) ); FociTokenRequest | where IncomingTokenType == "none" | join kind=inner ( FociTokenRequest | where IncomingTokenType != "none" | project-rename SecondAppDisplayName = AppDisplayName, SecondRequestTimeGenerated = TimeGenerated, SecondAppId = AppId ) on SessionId, UserPrincipalName | extend FirstOauthScopeInfo = extract("{\"key\":\"Oauth Scope Info\",\"value\":\"\\[(.*)\\]\"}", 1, AuthenticationProcessingDetails), SecondOauthScopeInfo = extract("{\"key\":\"Oauth Scope Info\",\"value\":\"\\[(.*)\\]\"}", 1, AuthenticationProcessingDetails1) | extend TimeDiff = datetime_diff('minute', SecondRequestTimeGenerated, TimeGenerated) | where TimeDiff >= 1 and TimeDiff <= maxTimeDiff | project FirstRequestTimeGenerated = TimeGenerated, FirstResult = ResultType, FirstResultDescription = ResultDescription, Identity, Location, FirstAppDisplayName = AppDisplayName, FirstAppId = AppId, ClientAppUsed, DeviceDetail, SecondDeviceDetail = DeviceDetail1, IPAddress, LocationDetails, UserAgent, SecondRequestTimeGenerated, SecondResult = ResultType, SecondResultDescription = ResultDescription1, SecondAppDisplayName, SecondAppId, SeconIncomingTokenType = IncomingTokenType1, SessionId, TimeDiff, FirstOauthScopeInfo, SecondOauthScopeInfo, FirstResourceIdentity = ResourceIdentity, SecondResourceIdentity = ResourceIdentity1 | where SecondAppDisplayName in ("Microsoft Azure CLI", "Copilot App", "Microsoft Azure PowerShell", "Visual Studio - Legacy", "Microsoft Edge Enterprise New Tab Page") and SecondResourceIdentity == "00000002-0000-0000-c000-000000000000" | where SecondResult == 0
'@
            Author = 'Robbe Van den Daele'
            AuthorURL = 'https://github.com/HybridBrothers/Hunting-Queries-Detection-Rules/blob/main/Entra%20ID/DetectSuspiciousFociTokenLoginsV2.md'
        },
        @{
            Id = "sensitiveMsGraphPermissions"
            Title = "Logins with access to sensitive Microsoft Graph permissions"
            Description = "The query retrieves sensitive Microsoft Graph permissions for ControlPlane tier and analyzes sign-in logs for Microsoft Graph with delegated scopes, including details about devices, authentication methods, and risk levels."
            Query = @'
let SensitiveMsGraphPermissions = externaldata(EAMTierLevelName: string, Category: string, AppRoleDisplayName: string)["https://raw.githubusercontent.com/Cloud-Architekt/AzurePrivilegedIAM/main/Classification/Classification_AppRoles.json"] with(format='multijson') | where EAMTierLevelName == "ControlPlane" | project AppRoleDisplayName; let SignInsWithDelegatedScope = union SigninLogs, AADNonInteractiveUserSignInLogs | where ResourceDisplayName == "Microsoft Graph" | extend JsonAuthProcDetails = parse_json(AuthenticationProcessingDetails) | extend JsonAuthCaeDetails = parse_json(AuthenticationProcessingDetails) | mv-apply JsonAuthProcDetails on ( where JsonAuthProcDetails.key startswith "Oauth Scope Info" | project OAuthDelegatedScope=JsonAuthProcDetails.value ) | mv-apply JsonAuthCaeDetails on ( where JsonAuthCaeDetails.key startswith "Is CAE Token" | project IsCaeToken=JsonAuthCaeDetails.value ) | extend DeviceDetail = iff(isempty( DeviceDetail_dynamic ), todynamic(DeviceDetail_string), DeviceDetail_dynamic) | extend DeviceName = tostring(toupper(DeviceDetail.displayName)) | extend DeviceOS = tostring(parse_json(DeviceDetail).operatingSystem) | extend DeviceTrust = tostring(parse_json(DeviceDetail).trustType) | extend DeviceCompliance = tostring(parse_json(DeviceDetail).isCompliant) | extend AuthenticationMethod = tostring(parse_json(AuthenticationDetails)[0].authenticationMethod) | extend AuthenticationDetail = tostring(parse_json(AuthenticationDetails)[0].authenticationStepResultDetail) | project TimeGenerated, CorrelationId, UserPrincipalName, RiskLevelDuringSignIn, RiskState, AppDisplayName, ResourceDisplayName, OAuthDelegatedScope, AuthenticationMethod, AuthenticationDetail, DeviceName, DeviceOS, DeviceTrust, DeviceCompliance, IsCaeToken; SignInsWithDelegatedScope
'@
            Author = 'Thomas Naunheim'
            AuthorURL = 'https://github.com/Cloud-Architekt/AzureSentinel/blob/main/Hunting%20Queries/EID-PrivilegedIdentities/SensitiveMicrosoftGraphDelegatedPermissionAccess.kusto'
        },
        @{
            Id = "usersWithPasskey"
            Title = "Users using Passkey for authentication"
            Description = "This query identifies users who have used Passkey as an authentication method in the last 30 days. It filters out common methods like 'Previously satisfied', 'Password', and 'Other' to focus on distinct MFA methods."
            Query = @'
SigninLogs | where TimeGenerated > ago(30d) | where UserType == "Member" | mv-expand todynamic(AuthenticationDetails) | extend ['Authentication Method'] = tostring(AuthenticationDetails.authenticationMethod) | where ['Authentication Method'] !in ("Previously satisfied", "Password", "Other") | where isnotempty(['Authentication Method']) | summarize ['List of MFA Methods']=make_set(['Authentication Method']) by UserPrincipalName | where  ['List of MFA Methods'] has "Passkey" 
'@
            Author = 'Jasper Baes'
            AuthorURL = 'https://www.linkedin.com/in/jasper-baes/'
        },
        @{
            Id = "usersWithSMS"
            Title = "Users using SMS authentication"
            Description = "This query identifies users who have used SMS as an authentication method in the last 30 days. It filters out common methods like 'Previously satisfied', 'Password', and 'Other' to focus on distinct MFA methods."
            Query = @'
SigninLogs | where TimeGenerated > ago(30d) | where UserType == "Member" | mv-expand todynamic(AuthenticationDetails) | extend ['Authentication Method'] = tostring(AuthenticationDetails.authenticationMethod) | where ['Authentication Method'] !in ("Previously satisfied", "Password", "Other") | where isnotempty(['Authentication Method']) | summarize ['List of MFA Methods']=make_set(['Authentication Method']) by UserPrincipalName | where  ['List of MFA Methods'] has "Text message" 
'@
            Author = 'Jasper Baes'
            AuthorURL = 'https://www.linkedin.com/in/jasper-baes/'
        },
        @{
            Id = "usersWithOnlySMS"
            Title = "Users using only SMS authentication"
            Description = "This query identifies users who have used SMS as their only authentication method in the last 30 days. It filters out common methods like 'Previously satisfied', 'Password', and 'Other' to focus on distinct MFA methods."
            Query = @'
SigninLogs | where TimeGenerated > ago(30d) | where UserType == "Member" | mv-expand todynamic(AuthenticationDetails) | extend ['Authentication Method'] = tostring(AuthenticationDetails.authenticationMethod) | where ['Authentication Method'] !in ("Previously satisfied", "Password", "Other") | where isnotempty(['Authentication Method']) | summarize ['List of MFA Methods']=make_set(['Authentication Method']) by UserPrincipalName | where tostring(['List of MFA Methods']) == tostring(dynamic(["Text message"]))
'@
            Author = 'Jasper Baes'
            AuthorURL = 'https://www.linkedin.com/in/jasper-baes/'
        }
    )

    $resultsTable = @()
    $i = 0

    # $queries = $queries | Select-Object -Last 2 # uncomment for development purposes, comment for production

    foreach ($q in $queries) {
        $percentComplete = [math]::Round(($i / $queries.Count) * 100)
        Write-Progress -Activity "     Running KQL queries for statistics..." -Status "$percentComplete% Complete" -PercentComplete $percentComplete

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

        $i++
    }

    return $resultsTable
}