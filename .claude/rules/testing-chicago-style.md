# Testing Discipline: Chicago School (Classicist), Not London School (Mockist)

## What "Chicago style" means

Two schools of unit-testing discipline, both internally coherent, not
interchangeable by accident:

- **Chicago school / classicist** (Kent Beck, Detroit): exercise **real**
  collaborators wherever practical (real objects, real subprocesses, real files on
  disk, a real local server) and assert on **final state** — the actual returned
  value, the actual file contents, the actual receipt/digest/decision. A test double
  appears only where a real collaborator is genuinely infeasible in-process (a paid
  third-party API, true nondeterminism you must pin, a destructive external side
  effect), and even then it is named as a deliberate, load-bearing exception, not a
  default.
- **London school / mockist** (the alternative this rule rejects as a default):
  isolate the unit under test by replacing every collaborator with a mock/stub, then
  assert on **interactions** — "was this method called, with these arguments." This
  style verifies the test's own model of the collaborator, not the real one; a test
  written this way can pass while the real integration is broken.

**Default to Chicago style.** Real collaborators, state-based assertions. This
applies regardless of language — Python, Rust, TypeScript, whatever the project is
in.

## What this means concretely

- Prefer a real subprocess over a stubbed function (`subprocess.run` against a real
  binary/script, not a monkeypatched return value).
- Prefer a real file on disk over an in-memory fake filesystem, when the code under
  test's job is to read/write files.
- Prefer a real local service over a mocked HTTP client, when a real local service is
  actually available (a locally-running model server, a local database, a real
  in-process object graph) — see the LLM-agent example below.
- Assert on the real returned/persisted state (return values, dataclass fields,
  file contents, computed digests, thrown exception messages) — never on "was this
  called," "was this called with X," or call-count assertions, as the primary check.
- A hand-written, simple, real implementation of an interface/protocol (e.g. a
  `PostconditionVerifier` that always returns `True`/`False` for a known reason) is
  **not** a mock — it is a real object with real, if simple, behavior. The
  distinction is not "is it hand-written" but "does it fake an interaction, or does
  it genuinely implement the collaborator's contract."

## Banned by default

- `unittest.mock`, `Mock()`, `MagicMock()`, `patch(...)`, `monkeypatch` (pytest) used
  to fake a collaborator this codebase owns or that is realistically runnable
  in-process/locally.
- Equivalent patterns in other languages/frameworks: Rust `mockall`-style trait mocks
  over your own traits, Jest `jest.mock()` / `jest.fn()` over your own modules, etc.,
  used the same way.
- Any test whose assertions are entirely interaction-based ("verify X was called")
  with no assertion on real resulting state.

## The one legitimate use of a test double

When a real collaborator is genuinely infeasible in-process — a paid external API
with side effects, a destructive operation, true unpinned nondeterminism — a test
double is allowed, but:

1. State explicitly, in the test or module docstring, *why* the real collaborator
   isn't used (not just that it isn't).
2. Prefer a real degraded/local alternative first if one exists (see below) before
   reaching for a mock.
3. Keep the double as a real, simple implementation of the same interface where
   possible (a fake), not an interaction-verifying mock, unless the interaction
   itself is the thing under test.

## Worked example from this session (autofde-lab)

Building an OCEL-driven optimization agent that needed an LLM's decision:

- **Wrong instinct** (rejected): mock the HTTP client, return a canned JSON tool-call
  response, assert the code parses it correctly. This tests the parsing code against
  a fabricated reply, not against a real model.
- **Chicago-correct fix** (what was actually done): use the real, already-running
  local model server (`~/turbo-fieldfare`'s TurboFieldfare/Gemma server on
  `127.0.0.1:8080`), make a real HTTP call with `temperature=0`, and assert on the
  real returned tool-call arguments. The test degrades to a **named, visible skip**
  (`pytest.mark.skipif(not is_server_available(), reason="...")`) on a machine
  without the server running — never a silent mock substitution.
- Every other collaborator in that same session (subprocess-based external solver
  wrapper, broker/receipt/replay chain, pydantic admission validation, a real
  `Astar` solve over a real maze domain) used real objects throughout, verified by
  re-running `grep -rn "unittest.mock\|Mock(\|MagicMock\|patch(\|monkeypatch"` over
  the test directories after every change and confirming zero matches, every time,
  as part of the completion evidence — not asserted once and assumed to hold.

## Verification requirement

When asked to confirm tests are "Chicago style" or "not cutting corners," the answer
is not a description — it is:

1. The real `grep` command run over the actual test directories, with its real
   output (ideally zero matches; if there are matches, name each one against the
   "one legitimate use" criteria above).
2. The real, currently-passing test run output (`pytest -v` or equivalent), not a
   memory of a prior run.

Both together, every time — an old passing run does not certify code changed since.

## See Also

- `~/.claude/rules/no-overclaiming-conversational.md` — grounding claims in a run,
  not a description; this rule is the testing-specific instance of that discipline.
- `~/.claude/rules/tools.md` — general tool-usage and markdown-authoring rules.
- `~/.claude/rules/no-overclaiming-rust.md` — for Rust test code specifically, this
  file owns the gate (whether a test double may exist at all — narrow justified
  exception only); that file's `MOCKED` status label only applies to a double this
  file's "one legitimate use" section has already permitted, not as a routine,
  freely-reachable status.
