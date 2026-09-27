# ADR-006 — Generation-Bound Cyber-Resiliency Manufacture

**Status:** accepted for v26.9.26 experimental implementation  
**Owner:** ggen_igniter manufacture boundary

## Decision

ggen_igniter admits a customer-visible generation profile before it may construct a
generation-bound resiliency plan.

The profile binds:

- generation identity;
- semantic-authority digest;
- source-snapshot digest;
- manufacture-policy digest;
- receipt digest;
- selected NIST SP 800-160 cyber-resiliency technique parameters;
- `implementation_inheritance = false`;
- `compatibility_obligation = false`;
- `authority_ceiling = :construct`;
- `disposition = :replaceable`.

The module is policy only. It does not deploy, delete, mutate, execute, or promote
anything. Consequential work remains behind the existing reconciliation / BRCE
authority boundary.

## Why

Traditional moving-target and non-persistence programs become expensive when each
change is a bespoke migration. ggen_igniter already treats generated artifacts as
replaceable projections, so many software-only changes can instead be bounded
manufacture parameters.

This does not make independent compute, storage, regions, networking, or failure
domains free. Redundancy is therefore explicitly classified as retaining intrinsic
resource cost.

## Information boundary

The public/runtime contract exposes only the invariants a consumer needs to verify.
It intentionally does not encode private generative theory.

## Consequences

A prior generation may be read as evidence, but its implementation receives no
standing merely because it existed. A transition plan preserves semantic capital,
source provenance, and receipts; it retires the prior implementation and does not
manufacture a compatibility obligation.

The transition plan carries `authority: :none`. A separate admitted consequence
path must perform any real retirement or manufacture.
