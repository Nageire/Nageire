# Ecosystems

Facts consulted from `review-dependency-bump`. Every command here is a read-only query; none installs a package or rewrites a lockfile.

## What each bot puts in the PR body, and what it leaves out

Dependabot:

- The title reads `Bump X from A to B`; a group reads `Bump the <group> group ... with N updates`; a git-source gem shows short SHAs instead of versions; `Bump X` with no versions means several versions or gems moved.
- The body holds collapsed blocks for release notes (taken from GitHub Releases), the changelog (taken from the CHANGELOG file at the new tag), and commits (ten of them plus a compare link), each cut off with "(truncated)".
- A "Maintainer changes" section appears when the publisher of the new version differs from the publisher of the old one.
- The compatibility score badge gives the share of public CI runs that passed for the same version transition; it prints `unknown` below five data points and is absent on grouped PRs.
- A security PR picks the lowest version that contains the fix and targets the default branch only.
- Transitive packages appear as "These dependencies needed to be updated together" with no notes of their own.

Renovate:

- The table has Package, Change, and the Merge Confidence columns: Age (age of the release), Adoption (share of Renovate users of the package on this release), Passing (share of updates whose tests passed), and Confidence (Low, Neutral, High, Very High).
- Majors default to Low confidence; an npm release under three days old cannot reach High because it can still be unpublished. Confidence exists for npm, RubyGems, PyPI, Maven, NuGet, Packagist, and Go modules only.
- Release notes come per version with a compare link, without the CHANGELOG text and without a commit list. Notes are missing when the registry record has no source URL, the repository is private, or tag names do not match versions.
- A configuration block says whether automerge is on and how rebasing works.
- A lockfile-only, `digest`, `pin`, or `lockFileMaintenance` update has no notes at all.

Neither bot says which APIs the codebase calls, what the other packages in the lockfile changed, whether `engines`, `peerDependencies`, or `required_ruby_version` moved, whether the license changed, whether the published artifact matches the repository, or whether a tag was moved.

## Version classes

- A `>=1.0` library follows semver: patch, minor, major. A `0.x` library gives no such promise, so a `0.x` minor counts as major; `^0.2.3` in npm allows patch moves only.
- A git SHA has no version class; the compare view between the two SHAs is the only description of the change.
- A Docker tag is not semver. A suffix names a variant, a codename change is an OS upgrade, precision is kept as written, and a digest-only change is a rebuild of the same tag.
- An Action referenced by a floating tag (`v6` to `v7`) changed major; an Action referenced by SHA is classified by the tag the version comment names, after the SHA is checked against that tag.
- A Terraform provider follows semver, but a `~>` constraint can leave the locked version unchanged when the manifest moves.

## Table

| Ecosystem | Where the changelog lives | See the effective change | Traps |
|---|---|---|---|
| RubyGems and Bundler | `changelog_uri` and `source_code_uri` in the gem metadata (`gem specification <gem> -v <v> --remote`, or the registry API at `/api/v2/rubygems/<gem>/versions/<v>.json`); GitHub Releases of that repository; the published-gem diff linked from the registry's version page | `Gemfile.lock` sections `GEM` (every locked version), `PLATFORMS`, `RUBY VERSION`, `BUNDLED WITH`, `CHECKSUMS`; `bundle outdated --only-explicit` (add `--strict` or `--filter-major`); `bundle info <gem>`; `bundle update <gem> --conservative` reproduces a minimal bump locally | Bundler moves shared sub-dependencies along with the named gem, and Dependabot runs it without `--conservative`; a gem's Ruby range changes per version; precompiled platform gems carry tighter Ruby ranges than the `ruby` platform, and `PLATFORMS` has to cover every deploy target (`bundle lock --add-platform <platform>`); a git-source gem bumps SHA to SHA with commits as the only notes; indirect updates are opt-in in the bot configuration |
| npm, pnpm, yarn | `repository.url` and `gitHead` from `npm view <pkg>@<v> repository.url gitHead`; GitHub Releases; `npm diff --diff=<pkg>@<a> --diff=<pkg>@<b>` for the published tarballs | `package-lock.json` `packages` entries, `pnpm-lock.yaml` `packages:` and `snapshots:`, `yarn.lock` entries; `npm explain <pkg>` and `pnpm why <pkg>` show who requires the package and with which range; `npm ls <pkg>`; `npm view <pkg>@<v> engines peerDependencies scripts` | `^0.x` allows patch moves only; `engines` and peer changes ship as minors; Dependabot bumps parents or removes sub-dependencies to fix a transitive advisory (npm only); `preinstall` and `postinstall` scripts run on install unless the package manager blocks builds; a version can be unpublished within 72 hours of release; linter minors add rules and errors; `@types/*` versions track the runtime library's major and minor, not their own API |
| GitHub Actions | GitHub Releases of the action repository; `gh api repos/O/R/compare/vA...vB`; `action.yml` at each tag (`gh api repos/O/R/contents/action.yml?ref=vX`) | The `uses:` lines in the diff; `gh api repos/O/R/git/ref/tags/vX` gives the object a tag points at (an annotated tag needs `gh api repos/O/R/git/tags/<sha>` to reach the commit); `gh attestation verify` when the release is attested | Tags are mutable, and a floating tag such as `v7` moves with every release; a full commit SHA is the only immutable reference; Dependabot updates the SHA and the `# vX` comment together but sometimes points at an untagged branch head, leaving the comment stale; Renovate skips bare SHAs without a version comment; a major often changes `runs.using` (the runtime) and the inputs at the same time |
| Docker images | Releases of the image's source repository when the image carries the `org.opencontainers.image.source` label and tags match; upstream release notes for official images | `FROM`, `COPY --from`, `RUN --mount`, and `# syntax=` lines; tag plus `@sha256:` digest; `docker manifest inspect <image>:<tag>` shows the digest a tag resolves to now | Tags are not semver: `-alpine` or `-bookworm` are variants, precision is preserved (`1.1` to `1.2`, never `1.2.0`), and a codename change is an OS upgrade; Dependabot updates a digest only when one is already pinned and does nothing for `latest`; a digest-only bump has no changelog because the same tag was rebuilt (OS packages, CVE fixes) |
| Terraform providers | The provider repository's `CHANGELOG.md`, which has `BREAKING CHANGES` sections, and the registry's upgrade guides | `.terraform.lock.hcl`: `version`, `constraints`, `hashes` (`h1:` content hashes, `zh:` zip hashes); `terraform providers lock -platform=<os_arch>` rewrites the hashes for a platform | Dependabot writes only the `h1:` hash for its own platform (linux_amd64), so `terraform init` fails on other platforms until the lock is regenerated; Renovate writes all platform hashes itself; a `~>` constraint can make the manifest bump a no-op for the locked version; a provider minor can change how existing configuration is accepted, and the plan is the real test |

## Notes

### RubyGems and Bundler

- When the `RUBY VERSION` or `PLATFORMS` section changed, the bot ran under a different Ruby or platform than the lockfile recorded; compare against `.ruby-version` and the deploy image.
- `bundle outdated --only-explicit` lists what the Gemfile names; without the flag it lists every locked gem, which shows how far a sub-dependency moved.
- A gem with `git:` plus `ref:` or `branch:` in the Gemfile is not on a released version. `tag:` names a release.

### npm, pnpm, yarn

- `npm view <pkg> time` prints the publish timestamp of every version; compare the new version's date against the repository's cooldown.
- `npm view <pkg> maintainers` lists the current maintainers; a name that is new since the old version and published the new one is a publisher change.
- `npm explain <pkg>` prints every path that requires the package with the range each path asks for. A peer range that excludes the new version names the companion for Step 6.
- `pnpm why <pkg> --json` does the same for pnpm; `-r` covers a workspace.
- A `resolved` field in the lockfile that points away from the public registry is a source change and a finding.

### GitHub Actions

- Compare the inputs the workflows pass with `inputs:` in `action.yml` at the new tag. The runner warns about an unknown input and does not fail, so a renamed input goes unnoticed until the behaviour changes.
- When a wrapper action in the repository pins upstream by SHA with a version comment, the bump has to move both, and the comment has to name a tag that exists.

### Docker images

- A Renovate Docker PR lists one row per `FROM` stage that uses the image; `-full` or `-slim` suffixes are variants, and each stage keeps its own.
- A tag change with the digest unchanged is a retag, not a rebuild; a digest change with the tag unchanged is a rebuild.

### Terraform providers

- After a Dependabot bump, `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64` (plus every platform the team uses) completes `hashes` before merge; the report names this as a follow-up.

## Supply-chain checks

| Check | How |
|---|---|
| Registry source matches the repository read | `npm view <pkg>@<v> repository.url`; `source_code_uri` in the gem metadata; the `source` label on an image |
| Version exists on the registry | `npm view <pkg> versions`; `gem list <gem> --remote --all`; `gh api repos/O/R/releases/tags/vX` |
| Publisher unchanged | Dependabot's "Maintainer changes" section; `npm view <pkg> maintainers`; the `authors` field of the gem metadata for both versions |
| Release age against the cooldown | `npm view <pkg> time`; `created_at` in the gem metadata; the Renovate Age column; `published_at` from `gh api repos/O/R/releases/tags/vX` |
| Install scripts | `npm view <pkg>@<v> scripts` for both versions; a new `preinstall`, `install`, or `postinstall` entry is a finding |
| Action SHA matches comment and release | `gh api repos/O/R/git/ref/tags/vX` (and `git/tags/<sha>` for an annotated tag) equals the SHA in `uses:` |
| Image digest belongs to the tag | `docker manifest inspect <image>:<tag>` equals the `@sha256:` in the `FROM` line |

## Bot commands and configuration used in follow-ups

- Dependabot comments: `@dependabot rebase`; `@dependabot recreate` (overwrites edits made to the branch); `@dependabot ignore this major version`; `@dependabot ignore this minor version`; `@dependabot ignore this dependency`; `@dependabot show <dependency> ignore conditions`.
- Dependabot configuration: `ignore:` with `update-types`; `groups:` with `patterns`; `cooldown:` with `default-days` and per-level days (not applied to security updates); `allow:` with `dependency-type: indirect` for Bundler and a few other ecosystems.
- Renovate: the rebase checkbox in the PR body; closing a PR ignores that update; `ignoreDeps`; `minimumReleaseAge`; `matchCurrentVersion: "!/^0/"` to keep `0.x` out of automerge; `rollbackPrs` when a version is unpublished; the `group:monorepos` preset to keep siblings together.
