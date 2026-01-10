#
# Copyright (c) 2025-present Takeshi Katano. All rights reserved.
# Disclaimer: The codes stored herein are my own personal codes and do not related my employer's any way.
#
param (
    [Parameter(Mandatory = $true)]
    [string] $TemplateFilePath,

    [Parameter(Mandatory = $true)]
    [string] $OutputFilePath
)

function Get-Placeholder
{
    param (
        [Parameter(Mandatory = $true)]
        [string] $TemplateContent
    )

    $placeholderPattern = '({{[^{}}]+}})'
    $matchResult = $TemplateContent | Select-String -AllMatches -Pattern $placeholderPattern
    $placeholders = $matchResult.Matches.Value | Select-Object -Unique
    return ,@($placeholders)
}

function Get-PlaceholderContext
{
    param (
        [Parameter(Mandatory = $true)]
        [string] $Placeholder
    )

    $trimedPlaceholder = $Placeholder.Trim('{', '}')
    $separatorPos = $trimedPlaceholder.Trim('{', '}').IndexOf(':')
    return [PSCustomObject]@{
        Service      = $trimedPlaceholder.Substring(0, $separatorPos)
        ServiceParam = $trimedPlaceholder.Substring($separatorPos + 1)
    }
}

function Get-ValueToReplaced
{
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $PlaceholderContext
    )

    switch ($PlaceholderContext.Service) {
        'github' {
            return Invoke-GitHubAction -ServiceParam $PlaceholderContext.ServiceParam
        }
        Default {
            Write-Error -Message ('Unknown provider: {0}' -f $_)
            return 'N/A: {0}' -f $_
        }
    }
}

function Invoke-GitHubAction
{
    param (
        [Parameter(Mandatory = $true)]
        [string] $ServiceParam
    )

    $context = Get-GitHubActionContext -ServiceParam $ServiceParam
    switch ($context.Api) {
        'repo' {
            switch ($context.Property) {
                'description' {
                    $result = Invoke-GitHubRestApiGetRepository -Owner $context.Owner -Repo $context.Repo
                    return $result.Description
                }
                'language' {
                    $result = Invoke-GitHubRestApiGetRepository -Owner $context.Owner -Repo $context.Repo
                    return $result.Language
                }
                'starsCount' {
                    $result = Invoke-GitHubRestApiGetRepository -Owner $context.Owner -Repo $context.Repo
                    return $result.StarsCount
                }
                'forksCount' {
                    $result = Invoke-GitHubRestApiGetRepository -Owner $context.Owner -Repo $context.Repo
                    return $result.ForksCount
                }
                'watchingCount' {
                    $result = Invoke-GitHubRestApiGetRepository -Owner $context.Owner -Repo $context.Repo
                    return $result.WatchingCount
                }
                'downloadCount' {
                    $result = Invoke-GitHubRestApiGetReleases -Owner $context.Owner -Repo $context.Repo
                    return $result.DownloadCount
                }
                'uniqueVisitors' {
                    $result = Invoke-GitHubRestApiGetPageViews -Owner $context.Owner -Repo $context.Repo
                    return $result.UniqueVisitors
                }
                'totalViews' {
                    $result = Invoke-GitHubRestApiGetPageViews -Owner $context.Owner -Repo $context.Repo
                    return $result.TotalViews
                }
                Default {
                    Write-Error -Message ('Unknown Property: {0}' -f $context.Property)
                    return 'N/A: {0}' -f $context.Property
                }
            }
        }
        Default {
            Write-Error -Message ('Unknown Api: {0}' -f $_)
            return 'N/A: {0}' -f $_
        }
    }
}

function Get-GitHubActionContext
{
    param (
        [Parameter(Mandatory = $true)]
        [string] $ServiceParam
    )

    $split = $ServiceParam.Split(',')
    return [PSCustomObject]@{
        Api      = $split[0]
        Owner    = $split[1]
        Repo     = $split[2]
        Property = $split[3]
    }
}

# Cache REST API result.
$GitHubRestApiResultCache = @{}

function Invoke-GitHubRestApiGetRepository
{
    param (
        [Parameter(Mandatory = $true)]
        [string] $Owner,

        [Parameter(Mandatory = $true)]
        [string] $Repo
    )

    $cacheKey = 'repos/{0}/{1}' -f $Owner, $Repo
    if ($GitHubRestApiResultCache.ContainsKey($cacheKey)) {
        return $GitHubRestApiResultCache[$cacheKey]
    }

    $result = [PSCustomObject] @{
        Description   = ''  # Description
        Language      = ''  # Language
        StarsCount    = 0   # Stars
        ForksCount    = 0   # Forks
        WatchingCount = 0   # Watching
    }

    try {
        # Retrieve the star count, watcher count, and fork count of the target repository.
        $params = @{
            Uri     = 'https://api.github.com/repos/{0}/{1}' -f $Owner, $Repo
            Method  = 'Get'
            Headers = @{
                Authorization = 'Bearer {0}' -f $env:GITHUB_TOKEN
            }
        }
        $response = Invoke-RestMethod @params

        $result.Description = $response.description
        $result.Language = $response.language
        $result.StarsCount = $response.stargazers_count
        $result.ForksCount = $response.forks_count
        $result.WatchingCount = $response.subscribers_count
    }
    catch {
        Write-Error -Message $_.Exception.Message
        $result.Description = 'N/A: {0}' -f $_.Exception.Message
        $result.Language = 'N/A: {0}' -f $_.Exception.Message
        $result.StarsCount = 'N/A: {0}' -f $_.Exception.Message
        $result.ForksCount = 'N/A: {0}' -f $_.Exception.Message
        $result.WatchingCount = 'N/A: {0}' -f $_.Exception.Message
    }

    $GitHubRestApiResultCache.Add($cacheKey, $result);
    return $result
}

function Invoke-GitHubRestApiGetReleases
{
    param (
        [Parameter(Mandatory = $true)]
        [string] $Owner,

        [Parameter(Mandatory = $true)]
        [string] $Repo
    )

    $cacheKey = 'repos/{0}/{1}/releases' -f $Owner, $Repo
    if ($GitHubRestApiResultCache.ContainsKey($cacheKey)) {
        return $GitHubRestApiResultCache[$cacheKey]
    }

    $result = [PSCustomObject] @{
        DownloadCount = 0
    }

    try {
        # Retrieve the release of the target repository.
        $params = @{
            Uri     = 'https://api.github.com/repos/{0}/{1}/releases' -f $Owner, $Repo
            Method  = 'Get'
            Headers = @{
                Authorization = 'Bearer {0}' -f $env:GITHUB_TOKEN
            }
        }
        $response = Invoke-RestMethod @params

        # Aggregate the download count of each release.
        $response | ForEach-Object -Process {
            $release = $_
            if (-not $release.draft) {
                $result.DownloadCount += [int] ($release.assets | Measure-Object -Sum -Property 'download_count').Sum
            }
        }
    }
    catch {
        Write-Error -Message $_.Exception.Message
        $result.DownloadCount = 'N/A: {0}' -f $_.Exception.Message
    }

    $GitHubRestApiResultCache.Add($cacheKey, $result);
    return $result
}

function Invoke-GitHubRestApiGetPageViews
{
    param (
        [Parameter(Mandatory = $true)]
        [string] $Owner,

        [Parameter(Mandatory = $true)]
        [string] $Repo
    )

    $cacheKey = 'repos/{0}/{1}/traffic/views' -f $Owner, $Repo
    if ($GitHubRestApiResultCache.ContainsKey($cacheKey)) {
        return $GitHubRestApiResultCache[$cacheKey]
    }

    $result = [PSCustomObject] @{
        UniqueVisitors = 0  # Unique visitors in last 14 days
        TotalViews     = 0  # Total views in last 14 days
    }

    try {
        # Retrieve the views of the target repository.
        $params = @{
            Uri     = 'https://api.github.com/repos/{0}/{1}/traffic/views' -f $Owner, $Repo
            Method  = 'Get'
            Headers = @{
                Authorization = 'Bearer {0}' -f $env:GITHUB_TOKEN
            }
        }
        $response = Invoke-RestMethod @params

        $result.UniqueVisitors = $response.uniques
        $result.TotalViews = $response.count
    }
    catch {
        Write-Error -Message $_.Exception.Message
        $result.UniqueVisitors = 'N/A: {0}' -f $_.Exception.Message
        $result.TotalViews = 'N/A: {0}' -f $_.Exception.Message
    }

    $GitHubRestApiResultCache.Add($cacheKey, $result);
    return $result
}


# Create placeholder and value pairs.
$replacePair = @{}
$templateContent = Get-Content -Encoding utf8 -Raw -LiteralPath $TemplateFilePath
$placeholders = Get-Placeholder -TemplateContent $templateContent
foreach ($placeholder in $placeholders) {
    $placeholderCtx = Get-PlaceholderContext -Placeholder $placeholder
    $value = Get-ValueToReplaced -PlaceholderContext $placeholderCtx
    $replacePair.Add($placeholder, $value)
}

# Create a README content that filled all placeholders.
foreach ($placeholder in $replacePair.Keys) {
    $value = $replacePair[$placeholder]
    $templateContent = $templateContent.Replace($placeholder, $value)
}
$templateContent | Set-Content -Encoding utf8 -Force -LiteralPath $OutputFilePath
