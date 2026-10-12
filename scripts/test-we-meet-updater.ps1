#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$testRoot = Join-Path $env:TEMP ('wemeet-updater-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$fixturePath = Join-Path $testRoot 'we-meet-x64.json'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\bucket\we-meet-x64.json') -Destination $fixturePath
$futureVersion = '99.12.34.567'
$futureUrl = "https://updatecdn.meeting.qq.com/cos/future/TencentMeeting_0300000000_${futureVersion}_x86_64.publish.officialwebsite.exe"
$futureAlias = $futureUrl + '#/dl.7z'
$sha = [System.Security.Cryptography.SHA256]::Create()
try { $key = ([BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($futureAlias)))).Replace('-', '').ToLowerInvariant().Substring(0,7) } finally { $sha.Dispose() }
$fixturePackage = Join-Path $testRoot ("we-meet-x64#$futureVersion#$key.7z")
[System.IO.File]::WriteAllText($fixturePackage, 'future package fixture')
$mockRelease = [pscustomobject]@{ channel='0300000000'; platform='windows_x86_64'; version=$futureVersion; url=$futureUrl; md5=(Get-FileHash -LiteralPath $fixturePackage -Algorithm MD5).Hash; size=(Get-Item -LiteralPath $fixturePackage).Length }
$mockResponse = [pscustomobject]@{ code=0; 'info-list'=@($mockRelease) }
function Invoke-RestMethod { param($Uri,$Headers,$TimeoutSec) return $mockResponse }
$updaterPath = Join-Path $PSScriptRoot 'update-we-meet-x64.ps1'
$beforeCheck = (Get-FileHash -LiteralPath $fixturePath).Hash
$check = & $updaterPath -ManifestPath $fixturePath -CacheDirectory $testRoot -CheckOnly
if (!$check.Changed -or $check.Version -ne $futureVersion -or (Get-FileHash -LiteralPath $fixturePath).Hash -ne $beforeCheck) { throw 'CheckOnly changed the manifest or missed a future release.' }
$update = & $updaterPath -ManifestPath $fixturePath -CacheDirectory $testRoot
$updatedManifest = Get-Content -LiteralPath $fixturePath -Raw -Encoding UTF8 | ConvertFrom-Json
$expectedSha = (Get-FileHash -LiteralPath $fixturePackage -Algorithm SHA256).Hash.ToLowerInvariant()
if ($updatedManifest.version -ne $futureVersion -or $updatedManifest.architecture.'64bit'.url -ne $futureAlias -or $updatedManifest.architecture.'64bit'.hash -ne ('sha256:' + $expectedSha)) { throw 'Future version, URL or SHA256 did not update together.' }
$noChange = & $updaterPath -ManifestPath $fixturePath -CacheDirectory $testRoot
if ($noChange.Changed) { throw 'Unchanged upstream should not rewrite the manifest.' }
$beforeFailure = (Get-FileHash -LiteralPath $fixturePath).Hash
$mockRelease.url = 'https://example.com/not-an-official-package.exe'
$rejected = $false
try { & $updaterPath -ManifestPath $fixturePath -CacheDirectory $testRoot | Out-Null } catch { $rejected = $true }
if (!$rejected -or (Get-FileHash -LiteralPath $fixturePath).Hash -ne $beforeFailure) { throw 'Invalid URL was accepted or damaged the manifest.' }
$mockRelease.url = $futureUrl
$mockResponse.code = 1
$rejected = $false
try { & $updaterPath -ManifestPath $fixturePath -CacheDirectory $testRoot | Out-Null } catch { $rejected = $true }
if (!$rejected -or (Get-FileHash -LiteralPath $fixturePath).Hash -ne $beforeFailure) { throw 'Failed API response was accepted or damaged the manifest.' }
Write-Host 'PASS: future releases, check-only, idempotence, URL validation and failure preservation.'
