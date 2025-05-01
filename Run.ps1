
# - Dislaimer: this script generates simulations based on the current implemented CA policies, not your desired state. If there are misconfigurations in your CA policies, these are also reflected in the tests
# + eerst object maken, dan testen uitschrijven (title, userID, UPN, conditions, actions)
# + testen voor alle included en excluded users, bij groepen max 5 (random gekozen)
# - een mooi overzichtje van alle testen in HTML (table)
# - in HTML: de maester test code met 'view more' knop en met copy paste knop
# - ook policies in reportOnly door een variabele te wijzigen
# - laatste lijn "generated X Maester test in 23 seconds"
# Issue: Users can still be excluded in another persona

$Global:CURRENTVERSION = "2025.18.1"
$Global:LATESTVERSION = ""
$Global:UPTODATE = $true 

Write-Host "`n ## Maester Conditional Access Generator ## " -NoNewline; Write-Host "v$CURRENTVERSION" -ForegroundColor DarkGray
Write-Host " Part of the Conditional Access Blueprint - https://jbaes.be/Conditional-Access-Blueprint" -ForegroundColor DarkGray
Write-Host " Created by Jasper Baes - https://github.com/jasperbaes/Maester-Conditional-Access-Generator`n" -ForegroundColor DarkGray

function Write-OutputError { param ( [string]$Message ) Write-Host " [" -ForegroundColor White -NoNewline; Write-Host "-" -ForegroundColor Red -NoNewline; Write-Host "] $Message" -ForegroundColor White }
function Write-OutputSuccess { param ( [string]$Message ) Write-Host " [" -ForegroundColor White -NoNewline; Write-Host "+" -ForegroundColor Green -NoNewline; Write-Host "] $Message" -ForegroundColor White }
function Write-OutputInfo { param ( [string]$Message ) Write-Host " [" -ForegroundColor White -NoNewline; Write-Host "i" -ForegroundColor Blue -NoNewline; Write-Host "] $Message" -ForegroundColor White }

try {
    # Fetch latest version from GitHub
    Write-OutputInfo "Checking version"
    $response = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/jasperbaes/Maester-Conditional-Access-Generator/main/assets/latestVersion.json'
    $LATESTVERSION = $response.latestVersion

    # If latest version from GitHub does not match script version, display update message
    if ($LATESTVERSION -ne $CURRENTVERSION) {
        $Global:UPTODATE = $false
        Write-OutputError "Update available! Run 'git pull' to update from $CURRENTVERSION --> $LATESTVERSION"
    } else {
        Write-OutputSuccess "Maester Conditional Access Generator version is up to date"
    }
} catch { }

# Import settings
Write-OutputInfo "Importing settings"
$jsonContent = Get-Content -Path "settings.json" -Raw | ConvertFrom-Json

$Global:TENANTID = $jsonContent.tenantID
$Global:CLIENTID = $jsonContent.clientID
$Global:CLIENTSECRET = $jsonContent.clientSecret
$Global:ORGANIZATIONNAME = $jsonContent.organizationName

# Check if Microsoft.Graph.Authentication module is installed
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    Write-OutputError "The Microsoft.Graph.Authentication module is not installed. Please install it first using the following command: 'Install-Module -Name Microsoft.Graph.Authentication'"
    Write-OutputError "Exiting script."
    Exit
} 

# Connect to Microsoft Graph
Write-OutputInfo "Connecting to Microsoft Graph"

$mgContext = Get-MgContext

if($mgContext) { # if already logged-in in the terminal
    Write-OutputSuccess "Connected to the Microsoft Graph with $((Get-MgContext).Account)"
} else {
    $clientSecret = ConvertTo-SecureString -AsPlainText $CLIENTSECRET -Force
    [pscredential]$clientSecretCredential = New-Object System.Management.Automation.PSCredential($CLIENTID, $clientSecret)
    Write-OutputInfo "No active MgGraph session detected. Connecting to Microsoft Graph with App Registration."

    # Check if TENANTID is empty
    if ([string]::IsNullOrWhiteSpace($Global:TENANTID)) {
        Write-OutputError "Error: TENANTID is empty. Please set the TenantID variable in settings.json. Exiting script."
        exit 1
    }

    # Check if CLIENTID is empty
    if ([string]::IsNullOrWhiteSpace($Global:CLIENTID)) {
        Write-OutputError "Error: CLIENTID is empty. Please set the clientID variable in settings.json. Exiting script."
        exit 1
    }

    # Check if CLIENTSECRET is empty
    if ([string]::IsNullOrWhiteSpace($Global:CLIENTSECRET)) {
        Write-OutputError "Error: CLIENTSECRET is empty. Please set the clientSecret variable in settings.json. Exiting script."
        exit 1
    }

    try { # Connect with App Registration
        Connect-MgGraph -TenantId $TENANTID -ClientSecretCredential $clientSecretCredential -NoWelcome -ErrorAction Stop
        Write-OutputSuccess "Connected to the Microsoft Graph"
    } catch {
        Write-OutputError "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
        Write-OutputError "Please login with 'Connect-MgGraph' command, or set the correct tenantID, clientID and clientSecret in settings.json and try again."
        Exit
    }
}

# Fetch Conditional Access policies
Write-OutputInfo "Fetching Conditional Access policies"
$conditionalAccessPolicies = Invoke-MtGraphRequest -RelativeUri "policies/conditionalAccessPolicies"
$conditionalAccessPolicies = $conditionalAccessPolicies | Select id, displayName, state, conditions, grantControls

if ($conditionalAccessPolicies.count -gt 0) {
    Write-OutputSuccess "$($conditionalAccessPolicies.count) Conditional Access policies detected"
} else {
    Write-OutputError "0 Conditional Access policies detected. Verify the credentials in settings.json are correct, the Service Principal has the correct permissions, and the tenant has Conditional Access policies in place. Exiting script."
    Exit
}

# Filter enabled policies
Write-OutputInfo "Filtering enabled Conditional Access policies"
$conditionalAccessPolicies = $conditionalAccessPolicies | Where-Object { $_.state -eq 'enabled' }
Write-OutputSuccess "$($conditionalAccessPolicies.count) enabled Conditional Access policies detected"

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
    # todo: if 'All' --> max 3 randoms

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
        $clientApp
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
    }
}

Write-OutputInfo "Generating Maester tests"

[array]$MaesterTests = @() # Create empty array

# Loop over all discovered Conditional Access Policies
foreach ($conditionalAccessPolicy in $conditionalAccessPolicies) {
    Write-OutputInfo "Generating Maester test for '$($conditionalAccessPolicy.displayName)' ($($conditionalAccessPolicy.id)) -- $($allUsers.count) users, $($allApplications.count) applications in test scope"

    # Get included and excluded users for tests
    [array]$allUsers = Get-CAPUsers $conditionalAccessPolicy.conditions.users
    [array]$allApplications = Get-CAPApplications $conditionalAccessPolicy.conditions.applications
    
    foreach ($user in $allUsers) { # loop over all users used in tests
        # Write-Output $user.UPN
        foreach ($app in $allApplications) { # loop over all applications used in tests
            # Write-Output "   $($app.applicationName)"
            foreach ($clientApp in $conditionalAccessPolicy.conditions.clientAppTypes) { # loop over all clientApps of the policy
                # Write-Output "   $($clientApp)"

                # - Country / IP 
                # - Country / IP (inverse) 
                # - SignInRiskLevel 
                # - SignInRiskLevel (inverse) 
                # - UserRiskLevel
                # - UserRiskLevel (inverse)
                # - DevicePlatform
                # - DevicePlatform (inverse)

                # if user and application are included
                if ($user.type -eq "included" -and $app.type -eq "included") {
                    if ($conditionalAccessPolicy.grantControls.builtInControls -contains "block") {
                        $testName = "$($user.UPN) should be blocked for application $($app.applicationName)"
                        $MaesterTests += Generate-MaesterTest $false 'block' $testName $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $conditionalAccessPolicy.conditions.clientAppTypes
                    }

                    if ($conditionalAccessPolicy.grantControls.builtInControls -contains "mfa") { # TODO: I think that if the action is 'passwordChange', then 'mfa' is also given as an action. To check. And to check if me must leave this out then...
                        $testName = "$($user.UPN) should have MFA for application $($app.applicationName)"
                        $MaesterTests += Generate-MaesterTest $false 'mfa' $testName $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $conditionalAccessPolicy.conditions.clientAppTypes
                    }

                    if ($conditionalAccessPolicy.grantControls.builtInControls -contains "passwordChange") { 
                        $testName = "$($user.UPN) should have a password reset for application $($app.applicationName)"
                        $MaesterTests += Generate-MaesterTest $false 'passwordChange' $testName $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $conditionalAccessPolicy.conditions.clientAppTypes
                    }

                    if ($conditionalAccessPolicy.grantControls.builtInControls -contains "compliantDevice") {
                        $testName = "$($user.UPN) should have a compliant device for application $($app.applicationName)"
                        $MaesterTests += Generate-MaesterTest $false 'compliantDevice' $testName $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $conditionalAccessPolicy.conditions.clientAppTypes
                    }
                }
                
                # if user or application are excluded --> inverted
                if ($user.type -eq "excluded" -or $app.type -eq "excluded") {
                    if ($conditionalAccessPolicy.grantControls.builtInControls -contains "block") {
                        $testName = "$($user.UPN) should not be blocked for application $($app.applicationName)"
                        $MaesterTests += Generate-MaesterTest $true 'block' $testName $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $conditionalAccessPolicy.conditions.clientAppTypes
                    }

                    if ($conditionalAccessPolicy.grantControls.builtInControls -contains "mfa") { # TODO: I think that if the action is 'passwordChange', then 'mfa' is also given as an action. To check. And to check if me must leave this out then...
                        $testName = "$($user.UPN) should not have MFA for application $($app.applicationName)"
                        $MaesterTests += Generate-MaesterTest $true 'mfa' $testName $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $conditionalAccessPolicy.conditions.clientAppTypes
                    }

                    if ($conditionalAccessPolicy.grantControls.builtInControls -contains "passwordChange") { 
                        $testName = "$($user.UPN) should not have a password reset for application $($app.applicationName)"
                        $MaesterTests += Generate-MaesterTest $true 'passwordChange' $testName $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $conditionalAccessPolicy.conditions.clientAppTypes
                    }

                    if ($conditionalAccessPolicy.grantControls.builtInControls -contains "compliantDevice") {
                        $testName = "$($user.UPN) should not have a compliant device for application $($app.applicationName)"
                        $MaesterTests += Generate-MaesterTest $true 'compliantDevice' $testName $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $conditionalAccessPolicy.conditions.clientAppTypes
                    }
                }
            }
        }
    }
}

Write-OutputSuccess "Generated $($MaesterTests.count) Maester tests"
# Write-Output $MaesterTests

##########################
# MAESTER TEST GENERATOR #
##########################


Write-OutputInfo "Translating to the Maester test layout"
$templateMaester = @"

Describe "$($ORGANIZATIONNAME).ConditionalAccess" {`n
"@

foreach ($MaesterTest in $MaesterTests) { 
    $templateMaester += "`n`tIt `"$($MaesterTest.testTitle)`" {`n"
    $templateMaester += "`t`t`$userId = $($MaesterTest.userID) # $($MaesterTest.UPN) `n"
    $templateMaester += "`t`t`$policiesEnforced = Test-MtConditionalAccessWhatIf -UserId `'$($MaesterTest.userID)`' "
    
    if ($MaesterTest.clientApp -ne "all") { # don't add to the test if 'all'
        $templateMaester += "-ClientAppType `'$($MaesterTest.clientApp)`' "
    }

    $templateMaester += "`n"

    if ($MaesterTest.inverted -eq $true) {
        $templateMaester += "`t`t`$policiesEnforced.grantControls.builtInControls | Should -Not -Contain `'$($MaesterTest.expectedControl)`' `n"
    } else {
        $templateMaester += "`t`t`$policiesEnforced.grantControls.builtInControls | Should -Contain `'$($MaesterTest.expectedControl)`' `n"
    }

    $templateMaester += "`t}`n"
}

$templateMaester += "}"
# $templateMaester # Uncomment for debugging purposes

Write-OutputSuccess "Translated to the Maester test layout"


# ##########
# # REPORT #
# ##########

Write-OutputInfo "Generating report"
$datetime = Get-Date -Format "dddd, MMMM dd, yyyy HH:mm:ss"

$template = @"
<!DOCTYPE html>
          <html lang="en">
            <head>
              <meta charset="UTF-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.5/dist/css/bootstrap.min.css" rel="stylesheet" integrity="sha384-SgOJa3DmI69IUzQ2PVdRZhwQ+dy64/BUtbMJw1MZ8t5HZApcHrRKUc4W0kG879m7" crossorigin="anonymous">
              <link rel="stylesheet" href="assets/fonts/AvenirBlack.ttf">
              <link rel="stylesheet" href="assets/fonts/AvenirBook.ttf">
              <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css">
              <style>
                @font-face {
                        font-family: mcgaFont;
                        src: url(./assets/fonts/AvenirBook.ttf);
                    }

                    @font-face {
                        font-family: mcgaFontBold;
                        src: url(./assets/fonts/AvenirBlack.ttf);
                    }

                    * {
                        font-family: mcgaFont !important
                    }

                    .font-bold {
                        font-family: mcgaFontBold !important
                    }

                    body { font-size: 1.2rem}

                    .color-primary { color: #27374d !important }
                    .color-secondary { color: #545454 !important }
                    .color-accent { color: #ff9142 !important }
                    .color-lightgrey { color:rgb(161, 161, 161) !important }

                    .bg-orange: { background-color: #ff9142 !important; }
                    .bg-lightorange { background-color: #ffe9db !important; border-radius: 10px; }
                    .bg-lightgrey { background-color: rgb(231, 231, 231) !important; border-radius: 10px; }
                    
                    .border-orange { border: 2px solid #ff9142 !important }
                    .border-grey { border: 1px solid #545454 !important }

                    h1 > span:nth-of-type(2) { color: #ff9142 !important; background-color: #ffe9db; border-radius: 15px;}
                    .badge { font-size: 1rem !important }
                    .small { font-size: 0.7rem !important }
                    th { color: #ff9142 !important; font-size: 1.4rem !important }
                    @keyframes pulse {
                        0% { transform: scale(1); }
                        50% { transform: scale(1.1); }
                        100% { transform: scale(1); }
                    }
                    .icon-pulse { display: inline-block; animation: pulse 2s infinite; }
              </style>
              <title>&#9889; Conditional Access Persona Report</title>
            </head>
            <body>
              <div class="container mt-5 mb-5">
                <h1 class="mb-0 text-center font-bold color-primary"> 
                    <span class="icon-pulse">&#9889;</span> Maester Conditional Access 
                    <span class="font-bold color-white px-2 py-0 ">Test Generator</span>
                </h1>
                <p class="text-center mt-3 mb-2 color-secondary">Automatically generate Maester test for your Conditional Access policies</p>

                <p class="text-center mt-3 mb-5 small text-secondary">$($datetime)</p>
"@        

# Show alert to update to new version
if ($UPTODATE -eq $false) {
    $template += @"

    <div class="alert alert-danger d-flex align-items-center alert-dismissible fade show" role="alert">
        <i class="bi bi-exclamation-circle me-3"></i>
        <div>
            <span class="font-bold">Update available!</span> Run 'git pull' to update from <em>$($CURRENTVERSION)</em> to <em>$($LATESTVERSION)</em>.
        </div>
        <button type="button" class="btn-close small mt-1" data-bs-dismiss="alert" aria-label="Close"></button>
    </div>
"@   
}

$template += @"
    <pre class="bg-lightgrey mt-3 px-5 py-0"><code>
    $($templateMaester)
    </code></pre>
"@

$template += @"
            <p class="text-center mt-5 mb-0"><a class="color-primary font-bold text-decoration-none" href="https://github.com/jasperbaes/Conditional-Access-Persona-Report" target="_blank">&#9889;Conditional Access Persona Report</a>, made by <a class="color-accent font-bold text-decoration-none" href="https://www.linkedin.com/in/jasper-baes" target="_blank">Jasper Baes</a></p>
            <p class="text-center mt-1 mb-0 small"><a class="color-secondary" href="https://github.com/jasperbaes/Conditional-Access-Persona-Report" target="_blank">https://github.com/jasperbaes/Conditional-Access-Persona-Report</a></p>
            <p class="text-center mt-1 mb-5 small">This tool is part of the <a class="color-secondary font-bold" href="https://jbaes.be/Conditional-Access-Blueprint" target="_blank">Conditional Access Blueprint</a>. Any commercial or organizational profit-driven usage is strictly prohibited.</p>
            
            <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.2.3/dist/js/bootstrap.bundle.min.js" integrity="sha384-kenU1KFdBIe4zVF0s0G1M5b4hcpxyD9F7jL+jjXkk+Q2h455rYXK/7HAuoJl+0I4" crossorigin="anonymous"></script>
            <script>
                const tooltipTriggerList = document.querySelectorAll('[data-bs-toggle="tooltip"]')
                const tooltipList = [...tooltipTriggerList].map(tooltipTriggerEl => new bootstrap.Tooltip(tooltipTriggerEl))
            </script>
        </body>
    </html>
"@

$filename = "$((Get-Date -Format 'yyyyMMddHHmm'))-$($ORGANIZATIONNAME)-ConditionalAccessPersonaReport.html"
$template | Out-File -FilePath $filename
Start-Process $filename
Write-OutputSuccess "Report available at: '$filename'`n"