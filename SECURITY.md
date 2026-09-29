<!-- NOTE for maintainers: private vulnerability reporting is currently DISABLED for
this repository. Enable Settings > Code security > Private vulnerability reporting,
then delete the "Interim channel" paragraph below and the matching interim wording in
CODE_OF_CONDUCT.md and .github/ISSUE_TEMPLATE/config.yml. -->

# Security Policy

## Supported versions

ggen_igniter uses CalVer. Only the latest published release (the latest published CalVer
release on hex.pm) is supported; fixes are made on `main` and released as a new version.

## Reporting a vulnerability

**Interim channel (private advisory reporting is not enabled yet).** Open a GitHub issue
at <https://github.com/seanchatmangpt/ggen_igniter/issues> titled "Security contact
request" with no technical details: do not describe the vulnerability, include a
reproduction, or name the affected component. A maintainer will move the conversation to
a private channel.

Once private vulnerability reporting is enabled for the repository, GitHub Security
Advisories will become the preferred path, and this file will be updated to say so.

Once a private channel exists, include the affected version, a reproduction, and the
impact you observed. Reports are
handled by the maintainer on a best-effort basis; no response or fix time is promised.

## Scope notes (facts about the current code)

- **Templates and packs are code.** Pack templates are EEx (`templates/*.eex`), and EEx
  evaluates arbitrary Elixir when rendered. Treat any pack from an untrusted source
  as code you are choosing to run, and read its templates before syncing it.
- **`mix ggen_igniter.pack.fetch` trust model** (`lib/ggen_igniter/pack.ex`,
  `fetch_pack!/2`). The `github:` source downloads GitHub's branch/ref archive, which
  publishes no checksum; the tool prints the archive's SHA-256 for you to record and
  compare, and does not verify it against anything. The `hex:` source compares the
  tarball's SHA-256 against the checksum hex.pm publishes for that release and refuses
  on mismatch. Archive extraction refuses subpaths that are absolute, contain `..`, or
  pass through a symlink.
- **Receipts are not signed.** Receipts under `.ggen_igniter/receipts/` are plain JSONL
  files with recorded digests; they carry no cryptographic signature, so they are
  evidence of a run, not authentication of its author.
- **Generated code runs with your privileges.** `sync` writes files into your project
  and, on the Reactor path, runs `mix compile` on the result.

Out of scope: vulnerabilities in third-party dependencies (report those upstream), and
issues that require running a malicious pack you chose to install.
