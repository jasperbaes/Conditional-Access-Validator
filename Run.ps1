param (
    [switch]$IncludeReportOnly,
    [switch]$SkipUserImpactMatrix,
    [int]$UserImpactMatrixLimit,
    [string]$RemovePersonaURL,
    [string]$AddPersonaURL
)

# Get current version
$jsonContent = Get-Content -Path "./assets/latestVersion.json" -Raw | ConvertFrom-Json

$Global:CURRENTVERSION = $jsonContent.latestVersion
$Global:LATESTVERSION = ""
$Global:UPTODATE = $true 

# Import functions.ps1
$subScriptpath = [System.IO.Path]::Combine($PSScriptRoot, 'functions.ps1')
. $subScriptpath

# Start the timer
$startTime = Get-Date

Write-Host "`n ## Conditional Access Validator ## " -ForegroundColor Cyan -NoNewline; Write-Host "v$CURRENTVERSION" -ForegroundColor DarkGray
Write-Host " Part of the Conditional Access Blueprint - https://jbaes.be/Conditional-Access-Blueprint" -ForegroundColor DarkGray
Write-Host " Created by Jasper Baes - https://github.com/jasperbaes/Maester-Conditional-Access-Test-Generator`n" -ForegroundColor DarkGray

try {
    # Fetch latest version from GitHub
    Write-OutputInfo "Checking version"
    $response = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/jasperbaes/Maester-Conditional-Access-Test-Generator/main/assets/latestVersion.json'
    $LATESTVERSION = $response.latestVersion

    # If latest version from GitHub does not match script version, display update message
    if ($LATESTVERSION -ne $CURRENTVERSION) {
        $Global:UPTODATE = $false
        Write-OutputError "Update available! Run 'git pull' to update from $CURRENTVERSION --> $LATESTVERSION"
    } else {
        Write-OutputSuccess "Conditional Access Validator version is up to date"
    }
} catch { }

# Import settings
Write-OutputInfo "Importing settings"
$jsonContent = Get-Content -Path "settings.json" -Raw | ConvertFrom-Json

$Global:TENANTID = $jsonContent.tenantID
$Global:CLIENTID = $jsonContent.clientID
$Global:CLIENTSECRET = $jsonContent.clientSecret

# Check if Microsoft.Graph.Authentication module is installed
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    Write-OutputError "The Microsoft.Graph.Authentication module is not installed. Please install it first using the following command: 'Install-Module -Name Microsoft.Graph.Authentication'"
    Write-OutputError "Exiting script."
    Exit
} 

# Connect to Microsoft Graph
Write-OutputInfo "Connecting to Microsoft Graph"

# Get current MgGraph session from the terminal
$mgContext = Get-MgContext

if([string]::IsNullOrEmpty($mgContext)) { # if a MgGraph session does not exist yet in the terminal
    Write-OutputInfo "No active MgGraph session detected. Checking your options..."

    # Check if App credentials are set in settings.json
    if ([string]::IsNullOrWhiteSpace($Global:TENANTID) -or [string]::IsNullOrWhiteSpace($Global:CLIENTID) -or [string]::IsNullOrWhiteSpace($Global:CLIENTSECRET)) {
        Write-OutputError "Failed to connect to Microsoft Graph"
        Write-OutputError "Please login with 'Connect-MgGraph' command, or set the tenantID, clientID and clientSecret in settings.json and try again."
    } else { # if app credentials are set in settings.json, then try to sign-in
        Write-OutputInfo "Connecting to the Microsoft Graph with application"

        $clientSecret = ConvertTo-SecureString -AsPlainText $CLIENTSECRET -Force
        [pscredential]$clientSecretCredential = New-Object System.Management.Automation.PSCredential($CLIENTID, $clientSecret)

        try { # Connect with App Registration
            Connect-MgGraph -TenantId $TENANTID -ClientSecretCredential $clientSecretCredential -NoWelcome -ErrorAction Stop
            $mgContext = Get-MgContext
            Write-OutputSuccess "Connected to the Microsoft Graph with Service Principal $($mgContext.AppName)"
        } catch {
            Write-OutputError "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
            Write-OutputError "Please login with 'Connect-MgGraph' command, or set the correct tenantID, clientID and clientSecret in settings.json and try again."
            Exit
        }
    }
} else { # if a MgGraph session already exists
    if (-not [string]::IsNullOrEmpty($mgContext.Account)) {
        Write-OutputSuccess "Connected to the Microsoft Graph with account $($mgContext.Account)"
    } elseif (-not [string]::IsNullOrEmpty($mgContext.AppName)) {
        Write-OutputSuccess "Connected to the Microsoft Graph with Service Principal $($mgContext.AppName)"
    }     
}

# Set organization tenant name
$Global:ORGANIZATIONNAME = (Get-MgOrganization).DisplayName

# Fetch Conditional Access policies
Write-OutputInfo "Fetching Conditional Access policies"
$conditionalAccessPolicies = Invoke-MgGraphRequest -Method GET 'https://graph.microsoft.com/v1.0/policies/conditionalAccessPolicies?$orderby=displayName'
$conditionalAccessPolicies = $conditionalAccessPolicies.value | Select id, displayName, state, conditions, grantControls

if ($conditionalAccessPolicies.count -gt 0) {
    Write-OutputSuccess "$($conditionalAccessPolicies.count) Conditional Access policies detected"
} else {
    Write-OutputError "0 Conditional Access policies detected. Verify the credentials in settings.json are correct, the Service Principal has the correct permissions, your user has the correct permissions or the tenant has Conditional Access policies in place. Exiting script."
    Exit
}

# Filter enabled policies
Write-OutputInfo "Filtering enabled Conditional Access policies"

if ($IncludeReportOnly) {
    $conditionalAccessPolicies = $conditionalAccessPolicies | Where-Object { $_.state -eq 'enabledForReportingButNotEnforced' -or  $_.state -eq 'enabled'}
} else {
    $conditionalAccessPolicies = $conditionalAccessPolicies | Where-Object { $_.state -eq 'enabled' }
}

Write-OutputSuccess "$($conditionalAccessPolicies.count) enabled Conditional Access policies detected"

Write-OutputInfo "Generating Maester tests"

[array]$MaesterTests = @() # Create empty array
$i = 0

# Loop over all discovered Conditional Access Policies
foreach ($conditionalAccessPolicy in $conditionalAccessPolicies) {
    # Write-OutputInfo "Generating Maester test for '$($conditionalAccessPolicy.displayName)' ($($conditionalAccessPolicy.id)) -- $($allUsers.count) users, $($allApplications.count) applications in test scope"
    $percentComplete = [math]::Round(($i / $conditionalAccessPolicies.Count) * 100)
    Write-Progress -Activity "     Generating Maester tests..." -Status "$percentComplete% Complete" -PercentComplete $percentComplete

    $testsCreatedForThisCAPolicy = 0

    # Get included and excluded users for tests
    [array]$allUsers = Get-CAPUsers $conditionalAccessPolicy.conditions.users
    [array]$allApplications = Get-CAPApplications $conditionalAccessPolicy.conditions.applications
    
    foreach ($user in $allUsers) { # loop over all users used in tests
        # Write-Output $user.UPN
        foreach ($app in $allApplications) { # loop over all applications used in tests
            # Write-Output "   $($app.applicationName)"

            # if all client apps are selected, then assign the common 3 client apps
            if ($conditionalAccessPolicy.conditions.clientAppTypes -eq "all") {
                $conditionalAccessPolicy.conditions.clientAppTypes = @("browser", "mobileAppsAndDesktopClients", "other")
            }

            foreach ($clientApp in $conditionalAccessPolicy.conditions.clientAppTypes) { # loop over all clientApps of the policy
                # Write-Output "   $($clientApp)"
                
                # Get all IP ranges. If the CA Policy does not use Named locations, an IP range with 'All' is returned. This 'empty' IP range is required to continue the foreach loop below.
                [array]$allIPRanges = Get-IPRanges $conditionalAccessPolicy.conditions.locations.includeLocations $conditionalAccessPolicy.conditions.locations.excludeLocations
                                
                foreach ($ipRange in $allIPRanges) { # loop over IP ranges
                    # Transform the IP range to an IP address
                    $ipRange.IPrange = $ipRange.IPrange.Split("/")[0]

                    # Get all device platforms
                    [array]$alldevicePlatforms = Get-devicePlatforms $conditionalAccessPolicy.conditions.platforms.includePlatforms $conditionalAccessPolicy.conditions.platforms.excludePlatforms                    

                    foreach ($devicePlatform in $alldevicePlatforms) { # loop over IP ranges

                        [array]$allUserRisks = $conditionalAccessPolicy.conditions.userRiskLevels
                        
                        # if no user risk levels are set, then set 'all'. This will not be printed in the test itself
                        if (-Not $conditionalAccessPolicy.conditions.userRiskLevels) {
                            $conditionalAccessPolicy.conditions.userRiskLevels = @('All')
                        } 

                        foreach ($userRisk in $conditionalAccessPolicy.conditions.userRiskLevels) { # loop over user risks

                            # - TODO: SignInRiskLevel 
                            # - TODO: Authenticationflow
                            # - TODO: DeviceProperties
                            # - TODO: InsiderRisk

                            # if user or app or IP range is excluded, we invert the test to a -Not
                            $invertedTest = $user.type -eq "excluded" -or $app.type -eq "excluded" -or $ipRange.type -eq "excluded" -or $devicePlatform.type -eq "excluded"
                            
                            if ($conditionalAccessPolicy.grantControls.builtInControls -contains "block") {
                                $testName = Create-TestName $invertedTest 'block' $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $clientApp $ipRange.IPrange $devicePlatform.OS $userRisk
                                $MaesterTests += Generate-MaesterTest $invertedTest 'block' $testName $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $clientApp $ipRange.IPrange $devicePlatform.OS $userRisk
                                $testsCreatedForThisCAPolicy++
                            }

                            if ($conditionalAccessPolicy.grantControls.builtInControls -contains "mfa") { # TODO: I think that if the action is 'passwordChange', then 'mfa' is also given as an action. To check. And to check if me must leave this out then...
                                $testName = Create-TestName $invertedTest 'mfa' $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $clientApp $ipRange.IPrange $devicePlatform.OS $userRisk
                                $MaesterTests += Generate-MaesterTest $invertedTest 'mfa' $testName $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $clientApp $ipRange.IPrange $devicePlatform.OS $userRisk
                                $testsCreatedForThisCAPolicy++
                            }

                            if ($conditionalAccessPolicy.grantControls.builtInControls -contains "passwordChange") { 
                                $testName = Create-TestName $invertedTest 'passwordChange' $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $clientApp $ipRange.IPrange $devicePlatform.OS $userRisk
                                $MaesterTests += Generate-MaesterTest $invertedTest 'passwordChange' $testName $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $clientApp $ipRange.IPrange $devicePlatform.OS $userRisk
                                $testsCreatedForThisCAPolicy++
                            }

                            if ($conditionalAccessPolicy.grantControls.builtInControls -contains "compliantDevice") {
                                $testName = Create-TestName $invertedTest 'compliantDevice' $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $clientApp $ipRange.IPrange $devicePlatform.OS $userRisk
                                $MaesterTests += Generate-MaesterTest $invertedTest 'compliantDevice' $testName $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $clientApp $ipRange.IPrange $devicePlatform.OS $userRisk
                                $testsCreatedForThisCAPolicy++
                            }

                            if ($conditionalAccessPolicy.grantControls.builtInControls -contains "domainJoinedDevice") {
                                $testName = Create-TestName $invertedTest 'domainJoinedDevice' $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $clientApp $ipRange.IPrange $devicePlatform.OS $userRisk
                                $MaesterTests += Generate-MaesterTest $invertedTest 'domainJoinedDevice' $testName $conditionalAccessPolicy.id $conditionalAccessPolicy.displayName $user.userID $user.UPN $app.applicationID $app.applicationName $clientApp $ipRange.IPrange $devicePlatform.OS $userRisk
                                $testsCreatedForThisCAPolicy++
                            }
                        }
                    }
                }
            }
        }
    }

    $i++
    Write-OutputSuccess "$testsCreatedForThisCAPolicy tests generated for '$($conditionalAccessPolicy.displayName)' ($($conditionalAccessPolicy.id))"
    # break # Uncomment for debugging purposes
}

Write-OutputSuccess "Generated $($MaesterTests.count) Maester tests"
# Write-Output $MaesterTests | ConvertTo-JSON

##########################
# MAESTER TEST GENERATOR #
##########################


Write-OutputInfo "Translating to the Maester code"
$templateMaester = @"

Describe "$($ORGANIZATIONNAME).ConditionalAccess" {`n
"@

foreach ($MaesterTest in $MaesterTests) { 
    $templateMaester += "`n`tIt `"$($MaesterTest.testTitle)`" {`n"
    $templateMaester += "`t`t`$userId = `'$($MaesterTest.userID)`' # $($MaesterTest.UPN) `n"
    $templateMaester += "`t`t`$policiesEnforced = Test-MtConditionalAccessWhatIf -UserId `$userId "
    $templateMaester += "-IncludeApplications `'$($MaesterTest.appID)`' "

    if ($MaesterTest.clientApp -ne "all") { # don't add to the test if 'all'
        $templateMaester += "-ClientAppType `'$($MaesterTest.clientApp)`' "
    } else {
        $MaesterTest.clientApp = '/' # set als '/' for the HTML report
    }

    if ($MaesterTest.IPRange -and $MaesterTest.IPRange -ne "All") {
        $templateMaester += "-Country 'FR' -IpAddress `'$($MaesterTest.IPRange)`' "
    } else {
        $MaesterTest.IPRange = '/' # set als '/' for the HTML report
    }

    if ($MaesterTest.devicePlatform -and $MaesterTest.devicePlatform -ne "All") {
        $templateMaester += "-DevicePlatform `'$($MaesterTest.devicePlatform)`' "
    } else {
        $MaesterTest.devicePlatform = '/' # set als '/' for the HTML report
    }

    if ($MaesterTest.userRisk -and $MaesterTest.userRisk -ne "All") { # the first letter must be uppercase (e.g.: 'Low', 'Medium', 'High')
        $templateMaester += "-UserRiskLevel `'$($MaesterTest.userRisk.Substring(0,1).ToUpper() + $MaesterTest.userRisk.Substring(1))`' "
    } else {
        $MaesterTest.userRisk = '/' # set als '/' for the HTML report
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

##############
# JSON CRACK #
##############

Write-OutputInfo "Generating flow chart"
$CAJSON = Get-ConditionalAccessFlowChart $MaesterTests
    
$filenameTemplate = "$((Get-Date -Format 'yyyyMMddHHmm'))-$($ORGANIZATIONNAME)-ConditionalAccessMaesterTests"
# $CAJSON | ConvertTo-Json -Depth 99 # Uncomment for debugging purposes
$CAjsonRaw = $CAJSON | ConvertTo-Json -Depth 99 # used in JSON Crack
Write-OutputSuccess "Generated flow chart"

######################
# User Impact Matrix #
######################

$userImpactMatrix = @()

if ($SkipUserImpactMatrix) {
    Write-OutputInfo "Skipping User Impact Matrix"
} else {
    $userImpactMatrix = Get-UserImpactMatrix $conditionalAccessPolicies $UserImpactMatrixLimit
    $columnNames = @($userImpactMatrix[0].Keys)
    $userImpactMatrix | Export-CSV -Path "$filenameTemplate.csv"
    Write-OutputSuccess "User Impact Matrix available at: '$filenameTemplate.csv'"
}

##################
# Persona Report #
##################

$PersonaReport = Get-PersonaReport $conditionalAccessPolicies

##################

$endTime = Get-Date # end script timer

$elapsedTime = $endTime - $startTime
$minutes = [math]::Floor($elapsedTime.TotalMinutes)
$seconds = $elapsedTime.Seconds

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

                    .bg-orange { background-color: #ff9142 !important; }
                    .bg-lightorange { background-color: #ffe9db !important; border-radius: 10px; }
                    .bg-lightgrey { background-color: rgb(242, 242, 242) !important; border-radius: 10px; }
                    
                    .border-orange { border: 2px solid #ff9142 !important }
                    .border-lightorange { border: 2px solid #ffe9db !important }
                    .border-grey { border: 1px solid #545454 !important }
                    .border-lightgrey { border: 2px solid rgb(218, 218, 218) !important }

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
                    .rounded { border-radius: 15px !important; }
                    button.active { color: #ff9142 !important }
                    .accordion-button:not(.collapsed) { background-color: white !important; }
                    .pointer:hover { cursor: pointer}
                    .table-matrix td { border-right: 1px solid #ffe9db !important; border-bottom: 1px solid #ffe9db !important }
                    .table-matrix tr td:last-child { border-right: none !important; }
                    .table-matrix tr:last-child { border-bottom: none !important; }
              </style>
              <title>&#9889; Conditional Access Validator</title>
            </head>
            <body>
              <div class="container mt-5 mb-5 position-relative">
                <h1 class="mb-0 text-center font-bold color-primary"> 
                    <span class="icon-pulse">&#9889;</span> Conditional Access 
                    <span class="font-bold color-white px-2 py-0 ">Validator</span>
                </h1>
                <p class="text-center mt-3 mb-2 color-secondary">Part of the <a href="https://jbaes.be/Conditional-Access-Blueprint" target="_blank" class="font-bold color-secondary">Conditional Access Blueprint</a> framework</p>
                <i class="bi bi-question-circle position-absolute pointer color-secondary" style="top: 10px; right: 10px;" data-bs-toggle="modal" data-bs-target="#infoModal"></i>

                <div class="modal fade" id="infoModal" tabindex="-1" aria-labelledby="exampleModalLabel" aria-hidden="true">
                    <div class="modal-dialog modal-lg modal-dialog-centered modal-dialog-scrollable">
                        <div class="modal-content">
                            <div class="modal-header">
                                <h1 class="modal-title fs-5 font-bold">About the Conditional Access Validator</h1>
                                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
                            </div>
                            <div class="modal-body">
                                <p>The goal of the Conditional Access Validator is to help you automatically validate the effectiveness of a Conditional Access setup.</p>
                                
                                <div class="alert alert-warning d-flex align-items-center fade show" role="alert">
                                    <i class="bi bi-exclamation-circle me-4"></i>
                                    <div class="">
                                        <p class="mb-0">This project is <span class="font-bold">open-source</span> and may contain errors, bugs or inaccuracies. If so, please create an <a href="https://github.com/jasperbaes/Maester-Conditional-Access-Test-Generator/issues" target="_blank" class="font-bold color-secondary">issue</a>. No one can be held responsible for any issues arising from the use of this project. </p>
                                    </div>
                                </div>

                                <p>The tool creates a set of Maester tests based on the current Conditional Access setup of the tenant, rather than the desired state. Therefore, the output might need adjustments to accurately represent the desired state.</p>
                                
                                <hr class="mt-3 mb-3 w-100"/>

                                <p>Here's how you can contribute to our mission:</p>

                                <ul>
                                    <li class="color-accent font-bold mb-0 mt-2">Use it: <span class="text-dark">Use the tool and other referenced tools of the <a class="color-secondary font-bold" href="https://jbaes.be/Conditional-Access-Blueprint" target="_blank">Conditional Access Blueprint</a>! That's why they were build.</span></li>
                                    <li class="color-accent font-bold mb-0 mt-2">Talk about it: <span class="text-dark">Engage in discussions about this, or invite me to spreak about the tool.</span></li>
                                    <li class="color-accent font-bold mb-0 mt-2">Feedback or share ideas: <span class="text-dark">Have ideas or suggestions to improve this tool? Message me on <a class="font-bold color-secondary" href="https://www.linkedin.com/in/jasper-baes" target="_blank">LinkedIn</a> (Jasper Baes)</span></li>
                                    <li class="color-accent font-bold mb-0 mt-2">Contribute: <span class="text-dark">Join efforts to improve the quality, code and usability of this tool.</span></li>
                                    <li class="color-accent font-bold mb-0 mt-2">Donate: <span class="text-dark">Consider supporting financially to cover costs (domain name, hosting, development costs, time, production costs, professional travel, ...) or future investments: donate on</span>
                                        <div class="mt-2">
                                            <a class="font-bold" href="https://www.buymeacoffee.com/jasperbaes" target="_blank"><button type="button" class="btn bg-orange text-white font-bold mb-3">☕ Buy Me A Coffee</button></a>
                                        </div>    
                                    </li>
                                </ul>
                                <p class="small text-secondary">The Conditional Access Validator was developed entirely on my own time, without any support or involvement from any organization or employer.</p>
                                <p class="small text-secondary">Please be aware that this project is only allowed for use by organizations seeking financial gain, on 2 conditions: 1. this is communicated to me over LinkedIn, 2. the header and footer of the HTML report is unchanged. Colors can be changed. Other items can be added.</p>
                                <p class="small text-secondary">Thank you for respecting these usage terms and contributing to a fair and ethical software community. </p>
                            </div>
                        </div>
                    </div>
                </div>

                <div class="d-flex justify-content-center mt-4">
                    <div class="row w-75">
                        <div class="col-4">
                            <div class="px-3 pt-4 pb-3 bg-white rounded border-lightorange" style="line-height: 0.5;"> 
                                <p class="font-bold my-0 fs-1 color-accent">$($conditionalAccessPolicies.count)<p>
                                <p class="font-bold my-0 fs-6 color-lightgrey">Conditional Access policies</p>
                            </div>
                        </div>
                        <div class="col-4">
                            <div class="px-3 pt-4 pb-3 bg-white rounded border-lightorange" style="line-height: 0.5;">
                                <p class="font-bold my-0 fs-1 color-accent">$($MaesterTests.count)<p>
                                <p class="font-bold my-0 fs-6 color-lightgrey">generated Maester tests</p>
                            </div>
                        </div>
                        <div class="col-4">
                            <div class="px-3 pt-4 pb-3 bg-white rounded border-lightorange" style="line-height: 0.5;">
                                <p class="font-bold my-0 fs-1 color-accent">$($minutes)<span class="fs-6">m</span>$($seconds)<span class="fs-6">s</span><p>
                                <p class="font-bold my-0 fs-6 color-lightgrey">time to generate</p>
                            </div>
                        </div>
                    </div>
                </div>
                               
                <p class="text-center mt-3 mb-5 small text-secondary">Generated on $($datetime) for $($ORGANIZATIONNAME)</p>
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

    <ul class="nav nav-tabs justify-content-center" id="myTab" role="tablist">
        <li class="nav-item" role="presentation">
            <button class="nav-link color-secondary font-bold px-4 active" id="code-tab" data-bs-toggle="tab" data-bs-target="#code-tab-pane" type="button" role="tab" aria-controls="code-tab-pane" aria-selected="true">Maester Code</button>
        </li>
        <li class="nav-item" role="presentation">
            <button class="nav-link color-secondary font-bold px-4" id="table-tab" data-bs-toggle="tab" data-bs-target="#table-tab-pane" type="button" role="tab" aria-controls="table-tab-pane" aria-selected="false">Simulation List</button>
        </li>
        <li class="nav-item" role="presentation">
            <button class="nav-link color-secondary font-bold px-4" id="flow-tab" data-bs-toggle="tab" data-bs-target="#flow-tab-pane" type="button" role="tab" aria-controls="flow-tab-pane" aria-selected="false">Flow Chart</button>
        </li>
        <li class="nav-item" role="presentation">
            <button class="nav-link color-secondary font-bold px-4" id="matrix-tab" data-bs-toggle="tab" data-bs-target="#matrix-tab-pane" type="button" role="tab" aria-controls="matrix-tab-pane" aria-selected="false">User Impact Matrix</button>
        </li>
        <li class="nav-item" role="presentation">
            <button class="nav-link color-secondary font-bold px-4" id="persona-report-tab" data-bs-toggle="tab" data-bs-target="#persona-report-tab-pane" type="button" role="tab" aria-controls="persona-report-tab-pane" aria-selected="true">Persona Report</button>
        </li>
        <li class="nav-item" role="presentation">
            <button class="nav-link color-secondary font-bold px-4" id="persona-tab" data-bs-toggle="tab" data-bs-target="#persona-tab-pane" type="button" role="tab" aria-controls="persona-tab-pane" aria-selected="true">Decision Tree</button>
        </li>
    </ul>


    <div class="tab-content" id="myTabContent">
      <div class="tab-pane fade show active" id="code-tab-pane" role="tabpanel" aria-labelledby="code-tab" tabindex="0">
            <div class="position-relative">
                <pre class="bg-lightgrey mt-3 px-5 py-0 border-lightgrey rounded">
                    <code id="templateMaester">
                        $($templateMaester)
                    </code>
                </pre>
                <div class="row position-absolute top-0 end-0 m-3"> 
                    <button class="btn btn-secondary col me-2 rounded" id="liveToastBtn" data-bs-toggle="tooltip" data-bs-title="Click to copy to clipboard">
                        <i class="bi bi-copy"></i>
                    </button>
                    <button class="btn btn-secondary col rounded" id="liveToastBtnDownload" data-bs-toggle="tooltip" data-bs-title="Click to download into your Maester project">
                        <i class="bi bi-download"></i>
                    </button>
                </div>
            </div>
            
            <div class="toast-container position-fixed bottom-0 end-0 p-3">
                <div id="liveToast" class="toast text-bg-secondary" role="alert" aria-live="assertive" aria-atomic="true">
                    <div class="toast-body font-bold">$($MaesterTests.count) Maester tests copied to clipboard!</div>
                </div>
            </div>
        </div>

        <div class="tab-pane fade show" id="table-tab-pane" role="tabpanel" aria-labelledby="table-tab" tabindex="1">
            <div class="accordion" id="accordionExample">
"@

$index = 0
foreach ($MaesterTest in $MaesterTests) { 
    $template += @"
        <div class="accordion-item">
            <h2 class="accordion-header">
                <button class="accordion-button font-bold text-secondary" type="button" data-bs-toggle="collapse" data-bs-target="#collapse$index" aria-expanded="true" aria-controls="collapse$index">
                    $($MaesterTest.testTitle)
"@                

if ($MaesterTest.inverted) {
    $template += @"
        <span class="badge rounded-pill bg-lightorange color-accent border-orange position-absolute end-0 me-5">no $($MaesterTest.expectedControl)</span>
"@   
} else {
    $template += @"
        <span class="badge rounded-pill bg-lightorange color-accent border-orange position-absolute end-0 me-5">$($MaesterTest.expectedControl)</span>
"@ 
}
              
    $template += @"
                </button>
            </h2>
            <div id="collapse$index" class="accordion-collapse collapse" data-bs-parent="#accordionExample">
                <div class="accordion-body">
                    <table class="table table-responsive table-sm fs-6 text-secondary">
                        <tbody class="text-secondary">
                            <tr>
                                <td>Conditional Access policy</td>
                                <td>$($MaesterTest.CAPolicyName)</td>
                            </tr>
                            <tr>
                                <td>Conditional Access policy ID</td>
                                <td>$($MaesterTest.CAPolicyID)</td>
                            </tr>
                             <tr>
                                <td>Expected control</td>
"@

                            if ($MaesterTest.inverted) { 
                                $template += "<td>no $($MaesterTest.expectedControl)</td>"
                            } else {
                                $template += "<td>$($MaesterTest.expectedControl)</td>"
                            }

$template += @"
                            </tr>
                             <tr>
                                <td>User ID</td>
                                <td>$($MaesterTest.userID)</td>
                            </tr>
                             <tr>
                                <td>UPN</td>
                                <td>$($MaesterTest.UPN)</td>
                            </tr>
                             <tr>
                                <td>Application</td>
                                <td>$($MaesterTest.appName)</td>
                            </tr>
                             <tr>
                                <td>Application ID</td>
                                <td>$($MaesterTest.appID)</td>
                            </tr>
                            
                             <tr>
                                <td>Client application</td>
                                <td>$($MaesterTest.clientApp)</td>
                            </tr>
                             <tr>
                                <td>IP range</td>
                                <td>$($MaesterTest.IPRange)</td>
                            </tr>
                             <tr>
                                <td>Device Platform</td>
                                <td>$($MaesterTest.devicePlatform)</td>
                            </tr>
                            <tr>
                                <td>User risk</td>
                                <td>$($MaesterTest.userRisk)</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>

"@
$index++
}


$template += @"
            </div>
        </div> 

        <div class="tab-pane fade show" id="flow-tab-pane" role="tabpanel" aria-labelledby="flow-tab" tabindex="2"> 
            <p class="small text-secondary mt-3 mb-1">If the chart below doesn't load, please refresh with this button:</p>
            <button class="btn btn-secondary rounded" onclick="refreshAllIframes()"  data-bs-toggle="tooltip" data-bs-title="Click to refresh the iframe">
                <i class="bi bi-arrow-clockwise ms-2"></i>
                Refresh 
            </button>
            <iframe class="mt-3 rounded" id="jsoncrackEmbed" src="https://jsoncrack.com/widget" width="100%" height="800px"></iframe>
        </div>
        
        <div class="tab-pane fade show" id="matrix-tab-pane" role="tabpanel" aria-labelledby="matrix-tab" tabindex="3">
            <a href="$($filenameTemplate).csv" target="_blank" class="btn bg-orange text-white rounded mt-2">
                <i class="bi bi-download me-2 ms-1"></i>
                Download full CSV ($($userImpactMatrix.count) users)
            </a>

            <table class="small table-matrix">
                <thead>
                    <tr>
"@                

foreach ($columnName in $columnNames) { 
    $template += @"
        <td class="p-2 font-bold">$($columnName)</td>
"@
}


$template += @"
                    </tr>
                </thead>
                <tbody>
"@   

foreach ($userImpactRow in ($userImpactMatrix | Select-Object -First 10)) {
    $template += "<tr>`n"

    foreach ($item in $userImpactRow.Values) {
        if ($item -eq $true) {
            $template += '    <td class="text-center p-2"> <i class="bi bi-check-circle-fill text-success"></i> </td>'
        } elseif ($item -eq $false) {
            $template += '    <td class="text-center p-2"> <i class="bi bi-x-circle-fill text-danger"></i> </td>'
        } else {
            $template += '   <td class="p-2"> ' + $item + ' </td>'
        }
    }

    $template += "</tr>`n"
}

     
$template += @"
                </tbody>
            </table>

            <p class="mt-5 mb-1"><i class="bi bi-check-circle-fill text-success me-3"></i>The user is included in the Conditional Access policy</p>
            <p><i class="bi bi-x-circle-fill text-danger me-3"></i>The user is excluded from the Conditional Access policy</p>

            <p class="mt-4 mb-1 font-bold">Next steps:</p>
            <ol>
                <li>Download and open the full CSV</li>
                <li>Select the full A column</li>
                <li>Go to the tab 'Data' and click 'Text to Columns'</li>
                <li>Select 'Delimited' and click Next</li>
                <li>Only select 'Comma' and click Finish</li>
                <li>Click on any cell with text and click 'Filter' in the 'Data' tab</li>
                <li><span class="font-bold">Review by filtering</span>1 or multiple columns, or search in columns</li>
                <li>Add Conditional Formatting rules for coloring 'TRUE' and 'FALSE'</li>
            </ol>
        </div>

        <div class="tab-pane fade show" id="persona-report-tab-pane" role="tabpanel" aria-labelledby="persona-report-tab" tabindex="4">
            <p class="text-secondary mt-3 mb-3">The primary goal of the <a class="color-secondary" href="https://jbaes.be/Conditional-Access-Blueprint" target="_blank">Conditional Access Blueprint</a> approach is to use a static set Conditional Access policies and only add/remove personas (=Entra groups) as needed. This report shows the personas per CA policy: </p> 

            <table class="table mb-5">
                    <thead>
                        <tr class="font-bold">
                            <th scope="col" class="font-bold">Conditional Access policy</th>
                            <th scope="col" class="font-bold">Included personas</th>
                            <th scope="col" class="font-bold">Excluded personas</th>
                        </tr>
                    </thead>

"@

foreach ($result in $PersonaReport) {
    $template += @"
        <tr>
            <td scope="col" class="font-bold color-secondary align-middle">$($result.policyName)
            <span class="badge rounded-pill text-bg-light small color-secondary bg-lightgrey">$($result.policyState)</span>
        </td>
        <td scope="col">
"@

    if ($RemovePersonaURL -eq "") {
        $usedRemovePersonaURL = "https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/PolicyBlade/policyId/$($result.policyID)"
    } else {
        $usedRemovePersonaURL = $RemovePersonaURL
    }

    if ($AddPersonaURL -eq "") {
        $usedAddPersonaURL = "https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/PolicyBlade/policyId/$($result.policyID)"
    } else {
        $usedAddPersonaURL = $AddPersonaURL
    }

    foreach ($includedGroup in $result.includedGroups) {
        $template += @"
        <div class="mt-1 mb-1">
            <a href="https://entra.microsoft.com/#view/Microsoft_AAD_IAM/GroupDetailsMenuBlade/~/Overview/groupId/$($includedGroup.groupID)" target="_blank" class="badge rounded-pill bg-lightorange color-accent border-orange position-relative text-decoration-none" data-bs-toggle="tooltip" data-bs-title="The Entra group '$($includedGroup.groupName)' has $($includedGroup.memberCount) member(s). Click to open the group in the Entra Portal.">
                $($includedGroup.groupName)
                <span class="position-absolute top-0 start-100 translate-middle badge rounded-pill text-white small" style="background-color: #ff9142 !important;">
                    $($includedGroup.memberCount)
                </span>
            </a>
            <a href="$($usedRemovePersonaURL)" target="_blank"><i class="bi bi-x ms-2 mt-1 color-accent" data-bs-toggle="tooltip" data-bs-title="Remove the Persona '$($includedGroup.groupName)' from the Conditional Access Policy '$($result.policyName)'."></i></a>
        </div>
"@    
    }

    $template += @"
                    <a href="$($usedAddPersonaURL)" target="_blank"><i class="bi bi-plus color-lightgrey" data-bs-toggle="tooltip" data-bs-title="Add a Persona to be included in the Conditional Access Policy '$($result.policyName)'."></i></a>
                </td>
                <td scope="col">
"@

    foreach ($excludedGroup in $result.excludedGroups) {
        $template += @"
        <div class="mt-1 mb-1">
            <a href="https://entra.microsoft.com/#view/Microsoft_AAD_IAM/GroupDetailsMenuBlade/~/Overview/groupId/$($excludedGroup.groupID)" target="_blank" class="badge rounded-pill bg-lightorange color-accent border-orange position-relative text-decoration-none" data-bs-toggle="tooltip" data-bs-title="The Entra group '$($excludedGroup.groupName)' has $($excludedGroup.memberCount) member(s). Click to open the group in the Entra Portal.">
                $($excludedGroup.groupName)
                <span class="position-absolute top-0 start-100 translate-middle badge rounded-pill text-white small" style="background-color: #ff9142 !important;">
                    $($excludedGroup.memberCount)
                </span>
                <a href="$($usedRemovePersonaURL)" target="_blank"><i class="bi bi-x ms-2 mt-1 color-accent" data-bs-toggle="tooltip" data-bs-title="Remove the Persona '$($includedGroup.groupName)' from the Conditional Access Policy '$($result.policyName)'."></i></a>
            </a>
        </div>
"@    
}

$template += @"
                    <a href="$($usedAddPersonaURL)" target="_blank"><i class="bi bi-plus color-lightgrey" data-bs-toggle="tooltip" data-bs-title="Add a Persona to be excluded from the Conditional Access Policy '$($result.policyName)'."></i></a>
                </td>
                <td scope="col">
"@
}
                
$template += @"
            </table>                 
                    
        </div> 

        <div class="tab-pane fade show" id="persona-tab-pane" role="tabpanel" aria-labelledby="persona-tab" tabindex="4">
            <p class="small text-secondary mt-3 mb-1">If the chart below doesn't load, please refresh with this button:</p>
            <button class="btn btn-secondary rounded" onclick="refreshAllIframes()"  data-bs-toggle="tooltip" data-bs-title="Click to refresh the iframe">
                <i class="bi bi-arrow-clockwise ms-2"></i>
                Refresh 
            </button>
            <iframe class="mt-3 rounded" src="https://www.jbaes.be/CAF/CA-flow" width="100%" height="800px"></iframe>
        </div> 

    </div>
"@

$template += @"
            <p class="text-center mt-5 mb-0"><a class="color-primary font-bold text-decoration-none" href="https://github.com/jasperbaes/Maester-Conditional-Access-Test-Generator" target="_blank">&#9889;Conditional Access Validator</a>, made by <a class="color-accent font-bold text-decoration-none" href="https://www.linkedin.com/in/jasper-baes" target="_blank">Jasper Baes</a></p>
            <p class="text-center mt-1 mb-0 small"><a class="color-secondary" href="https://github.com/jasperbaes/Maester-Conditional-Access-Test-Generator" target="_blank">https://github.com/jasperbaes/Maester-Conditional-Access-Test-Generator</a></p>
            <p class="text-center mt-1 mb-5 small">This tool is part of the <a class="color-secondary font-bold" href="https://jbaes.be/Conditional-Access-Blueprint" target="_blank">Conditional Access Blueprint</a>. Read the <a class="color-secondary font-bold" href="https://github.com/jasperbaes/Maester-Conditional-Access-Test-Generator?tab=readme-ov-file#-license" target="_blank">license</a> for info about organizational profit-driven.</p>
"@                     

$template += @"
            <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.2.3/dist/js/bootstrap.bundle.min.js" integrity="sha384-kenU1KFdBIe4zVF0s0G1M5b4hcpxyD9F7jL+jjXkk+Q2h455rYXK/7HAuoJl+0I4" crossorigin="anonymous"></script>
            <script>
                const toastTrigger = document.getElementById('liveToastBtn')
                const toastLiveExample = document.getElementById('liveToast')

                if (toastTrigger) {
                    const toastBootstrap = bootstrap.Toast.getOrCreateInstance(toastLiveExample)
                    toastTrigger.addEventListener('click', () => {
                        // Get the content of the code element
                        var codeContent = document.getElementById('templateMaester').textContent;

                        // Create a temporary textarea element
                        var tempTextarea = document.createElement('textarea');
                        tempTextarea.value = codeContent;
                        document.body.appendChild(tempTextarea);
                        
                        // Select the content of the textarea
                        tempTextarea.select();
                        tempTextarea.setSelectionRange(0, 99999);

                        // Copy the selected content to the clipboard
                        document.execCommand('copy');

                        // Remove the temporary textarea element
                        document.body.removeChild(tempTextarea);
                    
                        toastBootstrap.show()
                    })
                }

                const downloadTrigger = document.getElementById('liveToastBtnDownload');

                if (downloadTrigger) {
                    downloadTrigger.addEventListener('click', () => {
                        // Get the content of the code element
                        var codeContent = document.getElementById('templateMaester').textContent;

                        // Create a Blob with the code content
                        var blob = new Blob([codeContent], { type: 'text/plain' });

                        // Create a temporary anchor element
                        var downloadLink = document.createElement('a');
                        downloadLink.href = URL.createObjectURL(blob);
                        downloadLink.download = 'CA.Tests.ps1';

                        // Append the anchor, trigger the download, then remove it
                        document.body.appendChild(downloadLink);
                        downloadLink.click();
                        document.body.removeChild(downloadLink);
                    });
                }

                const jsonCrackEmbed = document.querySelector("#jsoncrackEmbed");

                let json = JSON.stringify($CAjsonRaw);
                let options = { theme: "light" }

                console.log(json)
                
                window?.addEventListener("message", (event) => {
                    jsonCrackEmbed.contentWindow.postMessage({
                    json, options
                    }, "*");
                });

                const tooltipTriggerList = document.querySelectorAll('[data-bs-toggle="tooltip"]')
                const tooltipList = [...tooltipTriggerList].map(tooltipTriggerEl => new bootstrap.Tooltip(tooltipTriggerEl))


                function refreshAllIframes() {
                    const iframes = document.querySelectorAll('iframe');
                    iframes.forEach(iframe => {
                        iframe.src = iframe.src;
                    });
                }

            </script>
        </body>
    </html>
"@

$template | Out-File -FilePath "$filenameTemplate.html"
Start-Process "$filenameTemplate.html"
Write-OutputSuccess "Report available at: '$filenameTemplate.html'`n"