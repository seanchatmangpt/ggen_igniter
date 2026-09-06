# ADR-0009: RuntimeShape as the shared admitted semantic IR

## Status

**Accepted with this PR.** The implementation is intentionally bounded to a
portable, content-addressed intermediate representation in
`GgenIgniter.RuntimeShape`; it does not yet add Ash/Spark/Reactor runtime
materialization, source promotion, SHACL evaluation, or consequential
actuation.

## Context

`ggen_igniter` already has a real reconciliation IR,
`GgenIgniter.PendingActuation`, for the final rendered filesystem delta. That
IR is deliberately actuation-oriented: it carries target paths, desired
content, prior hashes, ownership, and compensation data so the Reactor
pipeline can admit a whole change set before writing bytes.

The Ash-ecosystem work needs a different earlier boundary. One admitted
semantic graph may eventually project into several independently generated
surfaces:

- Ash resources/actions and consumer-side query lenses;
- Spark DSL structures;
- Reactor process graphs;
- Phoenix/AsyncAPI/GraphQL contracts;
- generated tests and receipts;
- durable Elixir source promoted through Igniter.

Using any one of those projections as the shared source would create a second
canonical model beside the upstream ontology/ggen graph. Reusing
`PendingActuation` would also collapse semantic construction into filesystem
actuation too early.

The required separation is:

```text
canonical ontology / ggen graph
            |
            v
      formal admission
            |
            v
       RuntimeShape
            |
      +-----+------+----------------+
      |            |                |
      v            v                v
  Ash/Spark     Reactor        contracts/tests
  projection    projection       /receipts
      |
      v
 PendingActuation (only when a source/filesystem projection is selected)
      |
      v
 admission -> actuation -> verification -> receipt
```

## Decision

Introduce `GgenIgniter.RuntimeShape` as a pure-data CONSTRUCT-time IR with the
following laws.

### 1. The ontology/graph remains canonical

A RuntimeShape is a bounded projection of already-admitted semantics. It is
not an editing surface and does not supersede the ontology/ggen graph.
Generated Ash, Reactor, AsyncAPI, Phoenix, GraphQL, test, or source artifacts
remain projections of the same semantic identity.

### 2. RuntimeShape contains portable data only

The constructor recursively refuses functions, PIDs, ports, references,
tuples, structs, and unsupported values. The IR must be serializable and
inspectable without loading Ash, Spark, Reactor, Phoenix, or provider-specific
runtime structs.

This preserves ADR-0002's existing boundary: Ash stays consumer-side and
optional in this repository.

### 3. Top-level fields are a closed vocabulary

`RuntimeShape.new/1` accepts only explicitly named fields. String-keyed input
is resolved through a literal case table; arbitrary external strings are
never converted with `String.to_atom/1`.

This makes the top-level schema fail closed and avoids turning an external
observation vocabulary into unbounded VM atoms.

### 4. Semantic identity is content-addressed

`shape_digest` is a deterministic `sha256:` digest over every semantic field
except `shape_digest` itself. Nested maps are recursively converted to sorted
key/value pairs before JSON encoding, making map insertion order irrelevant
while preserving list order as semantic.

The `sha256:` prefix intentionally matches the digest vocabulary already used
by `GgenIgniter.Receipt`; this ADR does not introduce a second hash vocabulary
inside this repository.

### 5. RuntimeShape never actuates

Constructing, validating, hashing, serializing, or projecting a RuntimeShape
must not itself cause an external consequence. A later projector may produce a
`PendingActuation`, Reactor plan, or other executable artifact, but the
existing admission/actuation/verification/receipt boundary remains the only
path to consequential DO.

## Consequences

### Positive

- one semantic identity can feed multiple Ash-ecosystem projections;
- Ash/Spark/Reactor remain implementations/projections rather than new
  canonical sources;
- runtime-discovered semantics can be compared, cached, receipted, and later
  promoted to source without changing identity;
- arbitrary external field names do not become atoms;
- future projectors can be added without coupling this core IR to optional
  consumer dependencies.

### Costs and disclosed limits

- this PR does not prove an Ash resource can yet be materialized from a
  RuntimeShape;
- SHACL/public-ontology admission still happens upstream of this struct in the
  current boundary and is not implemented here;
- implementation-native facets are retained as portable data, but no binding
  selector is implemented in this PR;
- runtime module-slot management, Manifest round-trip verification, source
  promotion, AsyncAPI projection, temporal semantics, metering, and BRCE
  integration remain follow-on work.

## Verification required for this ADR

The accompanying Chicago-style tests must prove at least:

1. nested map insertion order does not change `shape_digest`;
2. list order does change identity;
3. unknown top-level string fields are refused;
4. executable/runtime-only values are refused recursively;
5. required identity fields fail closed;
6. JSON encode/decode round-trips to the same semantic identity.

A future ADR or extension may add runtime Ash/Spark/Reactor materialization,
but it must consume this IR (or explicitly supersede this ADR with a
same-object falsifier) rather than introduce a parallel semantic source.
