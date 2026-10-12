#Requires -Version 5.1
[CmdletBinding()]
param (
    [string]$ManifestPath = (Join-Path $PSScriptRoot '..\bucket\we-meet-x64.json'),
    [string]$CacheDirectory = (Join-Path $env:TEMP 'my-scoop-bucket-wemeet-cache'),
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
$ManifestPath = [System.IO.Path]::GetFullPath($ManifestPath)
$manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$query = '[{"package-type":"app","channel":"0300000000","platform":"windows","arch":"x86_64"}]'
$apiUrl = 'https://meeting.tencent.com/web-service/query-download-info?q=' + [uri]::EscapeDataString($query) +
    '&nonce=' + [guid]::NewGuid().ToString('N').Substring(0,16) +
    '&c_os_model=web&c_instance_id=5&c_platform=0&c_lang=zh-cn&c_timestamp=' +
    [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + '&c_nonce=' + [guid]::NewGuid().ToString('N')
$response = Invoke-RestMethod -Uri $apiUrl -Headers @{ Referer = 'https://meeting.tencent.com/download/'; 'User-Agent' = 'Mozilla/5.0' } -TimeoutSec 30
$releases = @($response.'info-list' | Where-Object { $_.channel -eq '0300000000' -and $_.platform -eq 'windows_x86_64' })
if ($response.code -ne 0 -or $releases.Count -ne 1) { throw 'Official API did not return exactly one Windows x64 stable release.' }
$release = $releases[0]
if ($release.version -notmatch '^\d+\.\d+\.\d+\.\d+$') { throw 'Invalid release version.' }
$releaseUri = [uri]$release.url
$filenameMatch = [regex]::Match($releaseUri.AbsolutePath, '/TencentMeeting_0300000000_([\d.]+)_x86_64\..*exe$')
if ($releaseUri.Scheme -ne 'https' -or $releaseUri.Host -ne 'updatecdn.meeting.qq.com' -or
    !$filenameMatch.Success -or $filenameMatch.Groups[1].Value -ne $release.version -or
    $releaseUri.Fragment -or $releaseUri.Query) { throw 'Official release URL is not a matching trusted Windows x64 package.' }
if ($release.md5 -notmatch '^[a-fA-F0-9]{32}$' -or [long]$release.size -le 0) { throw 'Official package integrity metadata is missing.' }
if ([version]$release.version -lt [version]$manifest.version) { throw 'Refusing to downgrade the manifest.' }
$newUrl = $release.url + '#/dl.7z'
$pinnedPackageUrl = ($manifest.architecture.'64bit'.pre_install[0] -split "'")[1]
$changed = $manifest.version -ne $release.version -or $pinnedPackageUrl -ne $release.url
if ($CheckOnly -or !$changed) {
    [pscustomobject]@{ Version=$release.version; Url=$newUrl; Changed=$changed; ManifestPath=$ManifestPath }
    return
}
New-Item -ItemType Directory -Path $CacheDirectory -Force | Out-Null
# Match Scoop's cache key, including the filename alias in the URL hash.
$sha = [System.Security.Cryptography.SHA256]::Create()
try { $urlHash = ([BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($newUrl)))).Replace('-', '').ToLowerInvariant().Substring(0,7) } finally { $sha.Dispose() }
$cacheFile = Join-Path $CacheDirectory ('we-meet-x64#' + $release.version + '#' + $urlHash + '.7z')
$cacheValid = (Test-Path -LiteralPath $cacheFile) -and
    ((Get-Item -LiteralPath $cacheFile).Length -eq [long]$release.size) -and
    ((Get-FileHash -LiteralPath $cacheFile -Algorithm MD5).Hash -eq $release.md5)
if (!$cacheValid) {
    $partial = $cacheFile + '.download-' + [guid]::NewGuid().ToString('N')
    $client = New-Object System.Net.WebClient
    try {
        $client.Headers['Referer'] = 'https://meeting.tencent.com/'
        $client.Headers['User-Agent'] = 'Mozilla/5.0'
        Write-Host "Downloading official Windows x64 release $($release.version)..."
        $client.DownloadFile($release.url, $partial)
        if ((Get-Item -LiteralPath $partial).Length -ne [long]$release.size -or
            (Get-FileHash -LiteralPath $partial -Algorithm MD5).Hash -ne $release.md5) {
            throw 'Downloaded package does not match official size and MD5.'
        }
        Move-Item -LiteralPath $partial -Destination $cacheFile -Force
    } finally {
        $client.Dispose()
        if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
    }
}
$packageHash = (Get-FileHash -LiteralPath $cacheFile -Algorithm SHA256).Hash.ToLowerInvariant()
$manifest.version = $release.version
$manifest.architecture.'64bit'.pre_install[0] = '$packageUrl = ' + [char]39 + $release.url + [char]39
$manifest.architecture.'64bit'.pre_install[1] = '$packageSha256 = ' + [char]39 + $packageHash + [char]39
$tempManifest = $ManifestPath + '.tmp-' + [guid]::NewGuid().ToString('N')
try {
    [System.IO.File]::WriteAllText($tempManifest, ($manifest | ConvertTo-Json -Depth 20) + "`r`n", [System.Text.UTF8Encoding]::new($false))
    Get-Content -LiteralPath $tempManifest -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
    Move-Item -LiteralPath $tempManifest -Destination $ManifestPath -Force
} finally {
    if (Test-Path -LiteralPath $tempManifest) { Remove-Item -LiteralPath $tempManifest -Force }
}
[pscustomobject]@{ Version=$release.version; Url=$newUrl; Changed=$true; SHA256=$packageHash; ManifestPath=$ManifestPath }
