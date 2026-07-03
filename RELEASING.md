# Releasing a new version

A simple, repeatable checklist for shipping ProfessorNotch updates.

## Version numbers

ProfessorNotch uses **Semantic Versioning**: `MAJOR.MINOR.PATCH` (e.g. `1.0`, `1.1`, `2.0`).

| Change you made | New version | Example |
| --- | --- | --- |
| Only fixed bugs | bump **PATCH** | `1.0` → `1.0.1` |
| Added a feature (nothing broke) | bump **MINOR** | `1.0` → `1.1` |
| Big redesign / breaking change | bump **MAJOR** | `1.4` → `2.0` |

Every release **also** bumps the **build number** by 1 (`1`, `2`, `3`, …), no matter the version.
(Version = what users see; build number = an always-increasing counter Apple needs.)

## Steps to publish an update

1. **Bump the version in Xcode** — select the project → the app target → **General**:
   - **Version** → the new version, e.g. `1.1`  (this is `MARKETING_VERSION`)
   - **Build** → the next whole number, e.g. `2` (this is `CURRENT_PROJECT_VERSION`)

2. **Write down what changed** in `CHANGELOG.md`: add a new section under the version,
   listing what you Added / Changed / Fixed.

3. **Commit** the changes:
   ```bash
   git commit -am "Release 1.1"
   ```

4. **Tag and push** (the tag is how GitHub knows which commit the release points at):
   ```bash
   git tag v1.1
   git push origin main --tags
   ```

5. **Build the notarized app** (needs the one-time Apple Developer setup described at the
   top of `scripts/release.sh`):
   ```bash
   ./scripts/release.sh
   ```
   This produces `dist/ProfessorNotch.zip` — signed, notarized, and stapled, so users get
   no “unidentified developer” warning.

6. **Create the GitHub Release**: on the repo page → **Releases** → **Draft a new release**:
   - **Choose a tag:** `v1.1`
   - **Title:** `ProfessorNotch 1.1`
   - **Notes:** paste that version’s section from `CHANGELOG.md`
   - **Attach** `dist/ProfessorNotch.zip`
   - **Publish release**

That’s it. Users download the new `.zip`, replace the app in Applications, and they’re updated.

> Tip: the very first public release is **v1.0 / build 1** — already set in the project.
