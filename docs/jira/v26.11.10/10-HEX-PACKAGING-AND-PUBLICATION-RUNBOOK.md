# Requirement R3 — Hex Packaging & Production Publication Runbook

Operational procedure and step-by-step runbook for building, validating, and publishing
`ggen_igniter` to Hex.pm.

- **Release Version:** read from `mix.exs` `version:` (currently `26.11.18`; this runbook was first written for `26.11.10`)
- **Target Repository:** Hex.pm (`https://hex.pm/packages/ggen_igniter`)
- **Package Manifest Evidence:** [evidence/hex_package_manifest.txt](evidence/hex_package_manifest.txt) (snapshot from v26.11.10; re-record on publish)
- **Ash fence courts:** `test/ggen_igniter_package_ash_free_test.exs`, `test/ggen_igniter_shipped_packs_fence_test.exs`, `test/ws5_contracts/21_ash_dev_test_scope_test.exs`
- **Publication Authority:** Milestone M3 Operator Grant (operator must still run publish)

---

## 1. Scope & Objectives

Requirement R3 mandates:
1. Validating package metadata, version numbers, and file contents with `mix hex.build`.
2. Enforcing the Ash-free packaging fence and ensuring no OS-specific native binaries are bundled.
3. Conducting pre-flight checks and executing production publishing with `mix hex.publish`.
4. Verifying post-publication health on Hex.pm and Hexdocs.pm.

---

## 2. Pre-Flight Verification Checklist

Before initiating package publication, all of the following commands must execute cleanly with exit code 0:

```bash
# 1. Clean compilation check
mix compile --warnings-as-errors --force

# 2. Version policy verification
mix test test/ws5_contracts/16_version_contract_test.exs

# 3. Fleet receipt schema conformance
mix test test/ggen_igniter_fleet_receipt_conformance_test.exs

# 4. Package ash-free fence verification (deps scope + shipped_packs + real tarball)
mix test test/ws5_contracts/21_ash_dev_test_scope_test.exs \
  test/ggen_igniter_shipped_packs_fence_test.exs \
  test/ggen_igniter_package_ash_free_test.exs --include package

# 5. Full test suite execution
mix test

# 6. Mechanical documentation citation verification
bash docs/jira/v26.11.10/bin/check_doc_citations.sh

# 7. Hex user authentication check
mix hex.user whoami
```

---

## 3. Package Build & Manifest Verification

### 3.1 Unpack Tarball Inspection
Unpack the tarball into an isolated temporary directory and verify that the file listing matches the approved manifest:

```bash
TMP_DIR=$(mktemp -d)
mix hex.build --unpack -o "$TMP_DIR"

# Verify hex_metadata.config presence
test -f "$TMP_DIR/hex_metadata.config" && echo "hex_metadata.config present"

# Verify absence of compiled dynamic libraries
SO_COUNT=$(find "$TMP_DIR" -name "*.so" -o -name "*.dylib" | wc -l)
if [ "$SO_COUNT" -ne 0 ]; then
  echo "FATAL: Found compiled dynamic libraries in package!"
  exit 1
fi

# Record file count (v26.11.10 evidence was 501; do not treat that integer as a hard pin —
# assert the Ash / native fences below instead, then refresh evidence/hex_package_manifest.txt)
FILE_COUNT=$(find "$TMP_DIR" -type f | wc -l)
echo "Total unpacked files: $FILE_COUNT"

# Ash pack fence (only ash-manufacture-pack may appear under priv/ggen as an ash-named root)
find "$TMP_DIR/priv/ggen" -maxdepth 1 -type d -iname '*ash*' | sort
```

### 3.2 Metadata Audit
Examine `$TMP_DIR/hex_metadata.config` to verify:
- `name`: `"ggen_igniter"`
- `version`: matches `mix.exs` `version:` (e.g. `"26.11.18"`)
- `requirements`: Does not contain any `ash*` package name.
- `licenses`: Contains `["MIT"]`.

---

## 4. Publication Protocol

### 4.1 Step 1: Pre-Publish Dry Run
Execute `mix hex.publish --dry-run` to inspect package warnings and metadata resolution:

```bash
mix hex.publish --dry-run
```
- Verify that no warnings regarding uncommitted files or missing license files are emitted.
- Verify that the dependency list is correctly formatted.

### 4.2 Step 2: Production Publication
Publish the package to Hex.pm:

```bash
mix hex.publish --yes
```
- This command builds the `.tar` archive, generates the checksum, transmits the package to the Hex.pm API, and automatically pushes ExDoc documentation to Hexdocs.pm.

---

## 5. Post-Publication Verification

Immediately following publication, execute the verification ladder to ensure the release is live:

### 5.1 Package Registry Verification
```bash
VERSION=$(mix run -e 'IO.write Mix.Project.config()[:version]')
curl -s -f "https://hex.pm/api/packages/ggen_igniter/releases/${VERSION}" | grep "\"version\":\"${VERSION}\""
```
- Expected Result: HTTP 200 with JSON payload matching the published version.

### 5.2 Hexdocs Verification
```bash
VERSION=$(mix run -e 'IO.write Mix.Project.config()[:version]')
curl -s -I "https://hexdocs.pm/ggen_igniter/${VERSION}/readme.html" | grep "HTTP/2 200"
```
- Expected Result: HTTP 200 OK without redirects or 404s.

### 5.3 Consumer Installation Probe
Create a scratch Elixir project to verify dependency resolution from Hex:
```bash
VERSION=$(mix run -e 'IO.write Mix.Project.config()[:version]')
cd $(mktemp -d)
mix new hex_probe
cd hex_probe
# Add {:ggen_igniter, "~> ${VERSION}"} to mix.exs (pin the published CalVer)
mix deps.get
mix compile
```

---

## 6. Emergency Rollback Protocol

If a critical regression is discovered after publication:
1. **Note on Hex Immutability:** Hex.pm does not allow deleting or overwriting released packages once published.
2. **Retire the Release:**
   ```bash
   VERSION=$(mix run -e 'IO.write Mix.Project.config()[:version]')
   mix hex.retire ggen_igniter "$VERSION" --reason "invalid" --message "Critical regression identified; please use subsequent patch"
   ```
3. **Publish Shored-Up Patch:** Increment to the next CalVer tag and re-run this runbook.
