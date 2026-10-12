#Requires -Version 5.1
[CmdletBinding()]
param (
    [switch]$DownloadOnly,
    [switch]$UsePinnedVersion,
    [string]$CacheDirectory
)
$ErrorActionPreference = 'Stop'
if ($CacheDirectory -and !$DownloadOnly) { throw 'A custom CacheDirectory is supported only with DownloadOnly.' }
$manifestPath = Join-Path $PSScriptRoot '..\bucket\we-meet-x64.json'
$scoopHome = (& scoop prefix scoop | Select-Object -Last 1).Trim()
if (!(Test-Path -LiteralPath (Join-Path $scoopHome 'lib\core.ps1'))) { throw 'Cannot locate Scoop core.' }
. (Join-Path $scoopHome 'lib\core.ps1')
if ($CacheDirectory) { $cachedir = [System.IO.Path]::GetFullPath($CacheDirectory) }

if (!$UsePinnedVersion) {
    & (Join-Path $PSScriptRoot 'update-we-meet-x64.ps1') -ManifestPath $manifestPath -CacheDirectory $cachedir | Out-Null
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$package = $manifest.architecture.'64bit'
$downloadUrl = ([uri]$package.url).GetLeftPart([System.UriPartial]::Query)
$expectedHash = ($package.hash -replace '^sha256:', '').ToLowerInvariant()
if ($expectedHash -notmatch '^[a-f0-9]{64}$') { throw 'The manifest must contain a pinned SHA256 hash.' }
New-Item -ItemType Directory -Path $cachedir -Force | Out-Null
$packageCache = cache_path 'we-meet-x64' $manifest.version $package.url
$cacheValid = (Test-Path -LiteralPath $packageCache) -and
    ((Get-FileHash -LiteralPath $packageCache -Algorithm SHA256).Hash.ToLowerInvariant() -eq $expectedHash)
if (!$cacheValid) {
    $partialPath = $packageCache + '.download-' + [guid]::NewGuid().ToString('N')
    $client = New-Object System.Net.WebClient
    try {
        $client.Headers['Referer'] = $manifest.homepage
        $client.Headers['User-Agent'] = 'Mozilla/5.0'
        Write-Host "Downloading Tencent Meeting $($manifest.version) with the official Referer..."
        $client.DownloadFile($downloadUrl, $partialPath)
        $actualHash = (Get-FileHash -LiteralPath $partialPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $expectedHash) { throw "SHA256 mismatch. Expected $expectedHash; received $actualHash." }
        Move-Item -LiteralPath $partialPath -Destination $packageCache -Force
    } finally {
        $client.Dispose()
        if (Test-Path -LiteralPath $partialPath) { Remove-Item -LiteralPath $partialPath -Force }
    }
}
Write-Host "SHA256 verified: $expectedHash"
if (!$DownloadOnly) {
    if (installed 'we-meet-x64' $false) {
        . (Join-Path $scoopHome 'lib\manifest.ps1')
        $installedVersion = Select-CurrentVersion -AppName 'we-meet-x64'
        $sourceInfo = install_info 'we-meet-x64' $installedVersion $false
        if ($sourceInfo.bucket -or !$sourceInfo.url -or
            [System.IO.Path]::GetFullPath($sourceInfo.url) -ne [System.IO.Path]::GetFullPath($manifestPath)) {
            throw 'Existing installation uses another source. Reinstall from this repository manifest; automatic source switching is not performed.'
        }
        & scoop update we-meet-x64
    } else {
        & scoop install $manifestPath
    }
    if (!$?) { throw 'Scoop installation or update failed.' }
}
