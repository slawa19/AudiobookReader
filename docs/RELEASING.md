# Releasing and verifying Book AudioReader

Signed APKs of Book AudioReader are published in [GitHub Releases](https://github.com/slawa19/BookAudioReader/releases).
That is the only distribution channel (spec
003, R6). Every APK is built by the repository's own workflow,
[`.github/workflows/release.yml`](../.github/workflows/release.yml), from a `vX.Y.Z` tag, and is published with a
`SHA256SUMS` file and a build-provenance attestation.

- [For users](#for-users): download, verify, install.
- [For the maintainer](#for-the-maintainer): one-time setup, cutting a release, dry run, recovery.

## For users

### Download

Open the [latest release](https://github.com/slawa19/BookAudioReader/releases/latest) and download two files:

- `BookAudioReader-<version>.apk` — the app;
- `SHA256SUMS` — its SHA-256 checksum.

The APK works on Android 12 or newer (minSdk 31). All ABIs are in one file.

### Verify

Do at least step (b) or (c); step (a) only detects a damaged download.

**(a) Checksum.** In the folder with both files:

```
sha256sum -c SHA256SUMS
```

It must print `BookAudioReader-<version>.apk: OK`. On Windows (PowerShell) print the hash and compare it with the line
in `SHA256SUMS` (the case does not matter):

```
(Get-FileHash .\BookAudioReader-<version>.apk -Algorithm SHA256).Hash
```

A checksum proves only that the file was downloaded intact. It does not say who built it: whoever could replace the APK
on the release page could replace `SHA256SUMS` as well. Steps (b) and (c) answer that.

**(b) Build provenance.** Install the [GitHub CLI](https://cli.github.com/), log in once with `gh auth login` (any
GitHub account), then run:

```
gh attestation verify BookAudioReader-<version>.apk --repo slawa19/BookAudioReader --signer-workflow slawa19/BookAudioReader/.github/workflows/release.yml --source-ref refs/tags/v<version> --deny-self-hosted-runners
```

Replace `<version>` in both places (for example `0.1.0`). A successful result (`Verification succeeded!`) means that
GitHub holds a signed attestation, issued through Sigstore, for exactly this file (matched by its SHA-256 digest), and
that the command enforced each of these about the run that produced it:

- `--repo`: the run belonged to the repository `slawa19/BookAudioReader`;
- `--signer-workflow`: the attestation was signed by the workflow `.github/workflows/release.yml` of that repository,
  not by any other workflow;
- `--source-ref`: the run was started from the tag `v<version>`;
- `--deny-self-hosted-runners`: the run was on a GitHub-hosted runner.

The printed details also name the commit that was built. The command does not check that commit against anything you
choose; to do so, add `--source-digest <commit hash>`.

What this proves and what it does not is described in [What the checks prove](#what-the-checks-prove).

**(c) Signing certificate.** The APK is signed with the owner's permanent key. With the Android SDK build tools
(`apksigner`, in `build-tools/<version>/`):

```
apksigner verify --print-certs BookAudioReader-<version>.apk
```

The command must succeed, print exactly one signer, and its `certificate SHA-256 digest` must equal this fingerprint
(lowercase hexadecimal, no colons):

```
708d7a231f8ba86815ab3c2057526f0df31f8448860d0deff23ec200300bf563
```

The same fingerprint is stored in the repository variable `SIGNING_CERT_SHA256`, and the release workflow fails if the
APK it built is signed by any other certificate. The fingerprint must be the same for every release; a different one
means the APK is not from the same publisher.

### Install

1. Copy the APK to the phone, or download it there with the browser.
2. Open it from the browser's downloads or from a file manager. Android asks to allow installs from that app (the
   browser or the file manager): allow it for this one install. You can switch the permission off afterwards.
3. Confirm the installation.

The signing key is the same for every release, so a new version installs over the previous one and keeps your books
and reading positions. Android refuses an update whose build number (the part after `+` in `version:`) is lower than
the installed one; every release raises it. Installing an APK signed by a different key requires uninstalling the app first, which
deletes the books and positions.

The app does not narrate by itself: it needs your own Google Gemini API key, entered on the settings screen and kept in
Android's secure storage. Narration is billed by Google to that key. See [GEMINI_TTS.md](GEMINI_TTS.md) for the costs.

### What the checks prove

- **The attestation (b)**, with the flags above, proves that this APK file was produced by `release.yml` of
  `slawa19/BookAudioReader`, in a run started from the tag `v<version>`, on a GitHub-hosted runner. The workflow
  refuses to release a commit that is not on `main`. It identifies where the file came from. It does not prove that the source at
  that commit is free of bugs or malicious code; the source is public and can be read.
- **The signing certificate (c)** proves that the file is signed by the same key as earlier releases, that is, by the
  same publisher. The key is held in GitHub Secrets and on the owner's machine.
- **The checksum (a)** proves the download is intact.

Bit-for-bit reproducibility is **not** claimed (spec 003, "Out of scope"). Two builds of the same commit are not
guaranteed to give identical files, so nobody can verify the APK just by rebuilding and comparing hashes.

### Rebuild from the tag and compare contents

Anyone can rebuild the app from the tagged source with the same pinned toolchain and compare what is inside. This is
a manual inspection, not a proof:

```
git clone --branch v<version> https://github.com/slawa19/BookAudioReader.git
cd BookAudioReader
bash scripts/setup-wsl.sh
bash scripts/build-apk.sh --debug
```

`setup-wsl.sh` installs Flutter, the JDK and the Android SDK at the versions and checksums pinned in
`scripts/env.sh` (Linux x86_64; on Windows use WSL). The build-tools, NDK and CMake are exact versions, but the platform
package (`platforms;android-36`) is installed by name: `sdkmanager` cannot pin its revision, so a later revision may
be installed than the one a release was built with. `flutter pub get` runs with `--enforce-lockfile`, so the packages
are exactly those in `pubspec.lock`, and the Gradle distribution is checked against the checksum in
`android/gradle/wrapper/gradle-wrapper.properties`.

- `--debug` proves that the tagged source builds with the pinned toolchain, but a debug build is not comparable to the
  release APK: it is a different Flutter mode (no ahead-of-time compiled `libapp.so`) with a different signature.
- To compare with the release, build the release variant with a throwaway key of your own: create a keystore with
  `keytool -genkeypair`, put its path and passwords in `.env` following `.env.example`, and run
  `bash scripts/build-apk.sh`. Then unpack both APKs (`unzip -q -d official BookAudioReader-<version>.apk`, the same for
  `build/app/outputs/flutter-apk/app-real-release.apk`) and compare, for example,
  `diff -rq -x META-INF official rebuilt`. The signature block (`META-INF/`) will always differ, because the key
  differs. Other differences can occur even from the same source; they call for a look, but they are not by themselves
  evidence of tampering.

## For the maintainer

### What the workflow does

On a push of a tag `v*.*.*` (or a manual run), `release.yml`:

1. checks that the tag without `v` equals the version name in `pubspec.yaml` (the part before `+`), and, for a
   release (not a dry run), that the tagged commit is on `main` (an ancestor of `origin/main`); both checks run before
   any secret is read;
2. frees disk space on the runner, installs the pinned toolchain with `scripts/setup-wsl.sh`;
3. runs `scripts/test.sh` (analyzer and tests) — a release is never cut from a red tree; no signing secrets exist in
   the environment of this step;
4. restores the keystore from `ANDROID_KEYSTORE_BASE64` into `$RUNNER_TEMP` (never into the workspace), builds the
   release APK with `scripts/build-apk.sh`, and deletes the keystore in an `if: always()` step;
5. verifies the APK with `apksigner verify --print-certs` and fails if the certificate SHA-256 is not the one in the
   repository variable `SIGNING_CERT_SHA256`;
6. names the file `BookAudioReader-<version>.apk` and writes `SHA256SUMS`;
7. attests the APK with `actions/attest-build-provenance`;
8. creates the GitHub Release for the tag with both files attached and generated notes.

Third-party actions are pinned by full commit SHA (version in a trailing comment). To update one, look up the new
commit (`gh api repos/<owner>/<action>/git/ref/tags/<tag>`; if the object type is `tag`, resolve it once more to the
commit) and change the SHA and the comment together, in `release.yml` and `ci.yml`.

### One-time setup

Four secrets and one variable in the repository settings. None of the commands below puts a value on the command line
or into the shell history. Run them in the repository folder (or add `--repo slawa19/BookAudioReader`).

1. The keystore, as base64 **without line wraps** (the file holds the key; do not leave it in the repository folder
   and delete it afterwards). In WSL or Linux:

   ```
   base64 -w0 /path/to/audiobook-reader.jks > /tmp/keystore.b64
   gh secret set ANDROID_KEYSTORE_BASE64 < /tmp/keystore.b64
   shred -u /tmp/keystore.b64
   ```

   In PowerShell (the same file without line wraps; `-NoNewline` matters):

   ```
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\to\audiobook-reader.jks")) | Set-Content -NoNewline "$env:TEMP\keystore.b64"
   Get-Content -Raw "$env:TEMP\keystore.b64" | gh secret set ANDROID_KEYSTORE_BASE64
   Remove-Item "$env:TEMP\keystore.b64"
   ```

2. The passwords and the alias: run each command without a value and paste the value at the hidden prompt (the same
   values as in `.env`):

   ```
   gh secret set ANDROID_KEYSTORE_PASSWORD
   gh secret set ANDROID_KEY_ALIAS
   gh secret set ANDROID_KEY_PASSWORD
   ```

3. The expected signing certificate fingerprint, a repository **variable** (it is public by design). Get it from the
   keystore (`keytool -list -v -keystore <file> -alias <alias>` prints `SHA256: AA:BB:...`) or from an APK already
   signed with the key (`apksigner verify --print-certs`). Colons and case do not matter to the workflow:

   ```
   gh variable set SIGNING_CERT_SHA256 --body "<64 hexadecimal characters>"
   ```

   Put the same value, lowercase and without colons, into the `<SIGNING_CERT_SHA256>` line of this document.

4. Check: `gh secret list` shows the four secrets, `gh variable list` shows `SIGNING_CERT_SHA256`.

The keystore is the permanent key. Its loss or a password loss means that every user has to uninstall the app (losing
books and positions) to install a build signed with a new key. Keep a backup outside GitHub; GitHub Secrets cannot be
read back.

Secrets are repository-wide: anyone with write access can push a tag and run the workflow with them. A release is
refused unless the tagged commit is on `main`, but a dry run on any branch also builds with the signing key, so the
scripts of that branch run with the key. Keep the list of collaborators short.

Artifact attestations work only in public repositories (or on GitHub Enterprise). In a private repository the
attestation step fails and no release is created, so the first real release has to wait until the repository is public;
the dry run works at any time.

### Cut a release

1. Bump `version:` in `pubspec.yaml`. The part before `+` is the version name and must equal the tag; the number after
   `+` is the Android build number and must be higher than in the previous release (Android itself refuses only a
   lower one, but an equal number would leave two different builds with the same number).
2. Update `CHANGELOG.md`.
3. Commit, merge to `main`, and make sure CI on `main` is green (`gh run list`).
4. Tag a commit of `main` (the workflow refuses a tagged commit that is not on `main`) and push the tag:

   ```
   git tag v0.1.0
   git push origin v0.1.0
   ```

5. Watch the run: `gh run watch` (or the Actions tab). It does the same work as a CI run (toolchain install,
   analyzer, tests, build), so expect a similar time.
6. On success, open the release page, check that it has the APK and `SHA256SUMS`, and run the verification from
   [For users](#for-users) on the downloaded file once.

### Dry run

Actions → Release → Run workflow, keep `dry_run` ticked (or
`gh workflow run release.yml -f dry_run=true --ref <branch>`).
The workflow runs everything up to and including the signature check and uploads the APK and `SHA256SUMS` as a workflow
artifact (kept 7 days). It creates no release and no attestation, and it does not require the tag to exist or the
commit to be on `main`; if the chosen ref is a tag, the tag-versus-`pubspec.yaml` check still applies. Use it after any change to `release.yml`, the
build scripts or the secrets, and before the first release.

Running the workflow manually with `dry_run` off works only on a tag ref (`--ref v0.1.0`); it does the same as the tag
push.

### If the run fails after the tag was pushed

First read the failed step.

- **Nothing was published** (a failure before "Create the GitHub Release", which is the usual case, including a failed
  attestation): no release exists. For a transient failure (network, runner), use "Re-run failed jobs" on the run; it
  builds the same tagged commit. If the fix needs a code or workflow change, move the tag to the fixed commit, since
  nothing public points to it yet:

  ```
  git push origin :refs/tags/v0.1.0
  git tag -f v0.1.0 <fixed-commit-on-main>
  git push origin v0.1.0
  ```

- **"The tagged commit ... is not on main"**: the tag points to a commit of another branch. Merge the work into
  `main` and move the tag to a commit of `main` in the same way.
- **A wrong tag or version** ("The tag ... does not match the version name"): fix `pubspec.yaml` or the tag in the same
  way.
- **"A release for the tag already exists"**: a release was already created. If it is correct, nothing to do. If it
  must be replaced, delete it (`gh release delete v0.1.0 --cleanup-tag`), then follow the previous item.
- **The release was published but is wrong** (bad APK, wrong notes): once anyone may have downloaded it, do not reuse
  the tag. Delete the release (`gh release delete v0.1.0 --cleanup-tag`), fix the problem, and publish under a new
  version with a higher build number, and say so in `CHANGELOG.md`.
- **The signature check failed**: the key in `ANDROID_KEYSTORE_BASE64` or the variable `SIGNING_CERT_SHA256` is wrong.
  Do not edit the check; fix the secret or the variable, and re-run. An APK signed with a different key must never be
  published: it would not install over the previous releases.
