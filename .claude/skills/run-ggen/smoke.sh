#!/usr/bin/env bash
# Smoke-test driver for the `ggen` CLI (installed binary, ~/.local/bin/ggen).
# Proves the CLI is on PATH and the 5-stage sync pipeline (resolve, enrich,
# extract, render, write) actually runs end to end against a real,
# from-scratch ontology + SPARQL query + Tera template. Every step here was
# run for real before being written down -- see SKILL.md's "Verified"
# section for the transcript this was extracted from.
#
# Usage: bash smoke.sh [scratch-dir]   (default: a tmp dir, auto-cleaned)

set -euo pipefail

D="${1:-$(mktemp -d)}"
echo "== scratch dir: $D =="
mkdir -p "$D/ontology" "$D/queries" "$D/templates"
cd "$D"

command -v ggen >/dev/null || { echo "FAIL: ggen not on PATH"; exit 1; }
echo "== ggen version =="
ggen --version

cat > ontology/data.ttl <<'EOF'
@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
@prefix ex: <https://example.org/shapes#> .

ex:ThingShape a sh:NodeShape ;
    sh:targetClass ex:Thing ;
    sh:property
        [ sh:path ex:name ; sh:datatype xsd:string ; sh:minCount 1 ; sh:maxCount 1 ] .
EOF

# ORDER BY is REQUIRED -- ggen's strict_mode rejects any SELECT lacking it
# at config-validation time (error E0013), not just at query time.
cat > queries/extract.rq <<'EOF'
PREFIX sh: <http://www.w3.org/ns/shacl#>
SELECT ?shape ?targetClass ?propPath
WHERE {
  ?shape a sh:NodeShape ; sh:targetClass ?targetClass ; sh:property ?prop .
  ?prop sh:path ?propPath .
}
ORDER BY ?shape ?propPath
EOF

cat > templates/hello.tera <<'EOF'
// smoke test output
{% for row in sparql_results %}
// shape={{ row.shape }} prop={{ row.propPath }}
{% endfor %}
EOF

# output_dir + output_file are both relative to wherever ggen.toml itself
# lives (ggen resolves "ggen.toml" from cwd only -- there is no --manifest
# flag on this CLI version). Keep ggen.toml, the ontology, queries, and
# templates all under the same directory tree you invoke `ggen sync run`
# from.
cat > ggen.toml <<'EOF'
[project]
name = "ggen-smoke"
version = "1.0.0"
description = "smoke test"
authors = ["smoke"]
license = "MIT"

[ontology]
source = "ontology/data.ttl"
standard_only = false

[generation]
output_dir = "."

[[generation.rules]]
name = "hello"
query = { file = "queries/extract.rq" }
template = { file = "templates/hello.tera" }
output_file = "out/hello.rs"
mode = "Overwrite"
EOF

echo "== dry-run (no write) =="
ggen sync run --dry-run

echo "== real run =="
ggen sync run

echo "== generated output =="
cat out/hello.rs

grep -q "shape=https://example.org/shapes#ThingShape" out/hello.rs \
  && echo "SMOKE TEST PASSED" \
  || { echo "SMOKE TEST FAILED: expected content missing from out/hello.rs"; exit 1; }
