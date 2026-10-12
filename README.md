# Scoop Bucket Template

<!-- Uncomment the following line after replacing placeholders -->
<!-- [![Tests](https://github.com/<username>/<bucketname>/actions/workflows/ci.yml/badge.svg)](https://github.com/<username>/<bucketname>/actions/workflows/ci.yml) [![Excavator](https://github.com/<username>/<bucketname>/actions/workflows/excavator.yml/badge.svg)](https://github.com/<username>/<bucketname>/actions/workflows/excavator.yml) -->

Template bucket for [Scoop](https://scoop.sh), the Windows command-line installer.

## How do I use this template?

1. Generate your own copy of this repository with the "Use this template"
   button.
2. Allow all GitHub Actions:
   - Navigate to `Settings` - `Actions` - `General` - `Actions permissions`.
   - Select `Allow all actions and reusable workflows`.
   - Then `Save`.
3. Allow writing to the repository from within GitHub Actions:
   - Navigate to `Settings` - `Actions` - `General` - `Workflow permissions`.
   - Select `Read and write permissions`.
   - Then `Save`.
4. Document the bucket in `README.md`.
5. Replace the placeholder repository string in `bin/auto-pr.ps1`.
6. Create new manifests by copying `bucket/app-name.json.template` to
   `bucket/<app-name>.json`.
7. Commit and push changes.
8. If you'd like your bucket to be indexed on `https://scoop.sh`, add the
   topic `scoop-bucket` to your repository.

## How do I install these manifests?

After manifests have been committed and pushed, run the following:

```pwsh
scoop bucket add my-bucket https://github.com/zhy617/my-scoop-bucket
scoop install my-bucket/<manifestname>
```

## How do I contribute new manifests?

To make a new manifest contribution, please read the [Contributing
Guide](https://github.com/ScoopInstaller/.github/blob/main/.github/CONTRIBUTING.md)
and [App Manifests](https://github.com/ScoopInstaller/Scoop/wiki/App-Manifests)
wiki page.

## Tencent Meeting download workaround

The Tencent CDN can reject Scoop's automatically generated Referer with HTTP 403.
For `we-meet-x64`, run this from the repository root instead of a direct install:

```powershell
.\scripts\install-we-meet-x64.ps1
```

The script reads the version, URL and SHA256 from `bucket/we-meet-x64.json`,
downloads with the official homepage Referer, verifies the hash, and lets Scoop
install the local manifest from its cache. It does not change Scoop configuration.
To download and verify without installing, add `-DownloadOnly`.

### Automatic Tencent Meeting updates

The install script checks Tencent's official Windows x64 stable-release API before
installing. It updates this repository's manifest only after checking the official
package size and MD5, then computes a pinned SHA256. Running it again updates an
existing installation originally installed from this repository manifest.
Installations from another bucket are detected and are not silently switched.

Use `-UsePinnedVersion` to explicitly keep the manifest version when the API is
unavailable. To check upstream without downloading or editing the manifest:

```powershell
.\scripts\update-we-meet-x64.ps1 -CheckOnly
```

The existing Excavator workflow runs every four hours and now refreshes and commits
this manifest before updating the other apps. This requires pushing these changes,
enabling Actions, and allowing the workflow to write to the repository. It updates
the bucket manifest, not the software installed on your PC. Local installation or
updating still uses `scripts/install-we-meet-x64.ps1` so the correct Referer is used.