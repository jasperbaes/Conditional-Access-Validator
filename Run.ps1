
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

# Import functions.ps1
$subScriptpath = [System.IO.Path]::Combine($PSScriptRoot, 'functions.ps1')
. $subScriptpath

Write-Host "`n ## Maester Conditional Access Generator ## " -NoNewline; Write-Host "v$CURRENTVERSION" -ForegroundColor DarkGray
Write-Host " Part of the Conditional Access Blueprint - https://jbaes.be/Conditional-Access-Blueprint" -ForegroundColor DarkGray
Write-Host " Created by Jasper Baes - https://github.com/jasperbaes/Maester-Conditional-Access-Generator`n" -ForegroundColor DarkGray

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

Write-OutputInfo "Generating Maester tests"

[array]$MaesterTests = @() # Create empty array

# Loop over all discovered Conditional Access Policies
foreach ($conditionalAccessPolicy in $conditionalAccessPolicies) {
    Write-OutputInfo "Generating Maester test for '$($conditionalAccessPolicy.displayName)' ($($conditionalAccessPolicy.id)) -- $($allUsers.count) users, $($allApplications.count) applications in test scope"

    $testsCreatedForThisCAPolicy = 0

    # Get included and excluded users for tests
    [array]$allUsers = Get-CAPUsers $conditionalAccessPolicy.conditions.users
    [array]$allApplications = Get-CAPApplications $conditionalAccessPolicy.conditions.applications
    
    foreach ($user in $allUsers) { # loop over all users used in tests
        # Write-Output $user.UPN
        foreach ($app in $allApplications) { # loop over all applications used in tests
            # Write-Output "   $($app.applicationName)"
            foreach ($clientApp in $conditionalAccessPolicy.conditions.clientAppTypes) { # loop over all clientApps of the policy
                # Write-Output "   $($clientApp)"
                
                # Get all IP ranges. If the CA Policy does not use Named locations, an IP range with 'All' is returned. This 'empty' IP range is required to continue the foreach loop below.
                [array]$allIPRanges = Get-IPRanges $conditionalAccessPolicy.conditions.locations.includeLocations $conditionalAccessPolicy.conditions.locations.excludeLocations
                                
                foreach ($ipRange in $allIPRanges) { # loop over IP ranges
                    # - SignInRiskLevel 
                    # - SignInRiskLevel (inverse) 
                    # - UserRiskLevel
                    # - UserRiskLevel (inverse)
                    # - DevicePlatform
                    # - DevicePlatform (inverse)

                    # if user or app or IP range is excluded, we invert the test to a -Not
                    $invertedTest = $user.type -eq "excluded" -or $app.type -eq "excluded" -or $ipRange.type -eq "excluded"
                    
                    if ($conditionalAccessPolicy.grantControls.builtInControls -contains "block") {
                        $testName = if ($invertedTest) { "$($user.UPN) should not be blocked for application $($app.applicationName)" } else { "$($user.UPN) should be blocked for application $($app.applicationName)" }
                        $MaesterTests += Generate-MaesterTest $invertedTest 'block' $testName $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $conditionalAccessPolicy.conditions.clientAppTypes $ipRange.IPrange
                        $testsCreatedForThisCAPolicy++
                    }

                    if ($conditionalAccessPolicy.grantControls.builtInControls -contains "mfa") { # TODO: I think that if the action is 'passwordChange', then 'mfa' is also given as an action. To check. And to check if me must leave this out then...
                        $testName = if ($invertedTest) { "$($user.UPN) should not have MFA for application $($app.applicationName)" } else { "$($user.UPN) should have MFA for application $($app.applicationName)" }
                        $MaesterTests += Generate-MaesterTest $invertedTest 'mfa' $testName $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $conditionalAccessPolicy.conditions.clientAppTypes $ipRange.IPrange
                        $testsCreatedForThisCAPolicy++
                    }

                    if ($conditionalAccessPolicy.grantControls.builtInControls -contains "passwordChange") { 
                        $testName = if ($invertedTest) { "$($user.UPN) should not have a password reset for application $($app.applicationName)" } else { "$($user.UPN) should have a password reset for application $($app.applicationName)" }
                        $MaesterTests += Generate-MaesterTest $invertedTest 'passwordChange' $testName $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $conditionalAccessPolicy.conditions.clientAppTypes $ipRange.IPrange
                        $testsCreatedForThisCAPolicy++
                    }

                    if ($conditionalAccessPolicy.grantControls.builtInControls -contains "compliantDevice") {
                        $testName = if ($invertedTest) { "$($user.UPN) should not have a compliant device for application $($app.applicationName)" } else { "$($user.UPN) should have a compliant device for application $($app.applicationName)" }
                        $MaesterTests += Generate-MaesterTest $invertedTest 'compliantDevice' $testName $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $conditionalAccessPolicy.conditions.clientAppTypes $ipRange.IPrange
                        $testsCreatedForThisCAPolicy++
                    }
                    
                }
            }
        }
    }

    Write-OutputSuccess "$testsCreatedForThisCAPolicy tests created for '$($conditionalAccessPolicy.displayName)' ($($conditionalAccessPolicy.id))"
}

Write-OutputSuccess "Generated $($MaesterTests.count) Maester tests"
Write-Output $MaesterTests

##########################
# MAESTER TEST GENERATOR #
##########################


Write-OutputInfo "Translating to the Maester code"
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

    if ($MaesterTest.IPRange -and $MaesterTest.IPRange -ne "All") {
        $templateMaester += "-Country FR -IpAddress `'$($MaesterTest.IPRange)`' "
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