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
            Description = "Finds applications using an unique IP address for sign-ins, excluding managed identities."
            Query = 'AADSpnSignInEventsBeta | where ErrorCode == 0 | where IsManagedIdentity == 0 | summarize UniqueIPCount = dcount(IPAddress) by ApplicationId | where UniqueIPCount == 1 | join kind=leftouter ( AADSpnSignInEventsBeta | summarize by ApplicationId, IPAddress, ServicePrincipalName) on $left.ApplicationId == $right.ApplicationId | project IPAddress, ServicePrincipalName, ApplicationId'
            Author = ''
            AuthorURL = ''
        }
    )

    $resultsTable = @()

    foreach ($q in $queries) {
        $result = Invoke-HuntingQuery -Query $q.Query
        $resultsTable += [PSCustomObject]@{
            Id = $q.Id
            Description = $q.Description
            ResultAmount = $result.Count
            Result = $result.results
            Author = $q.Author
            AuthorURL = $q.AuthorURL
        }
    }

    return $resultsTable
}