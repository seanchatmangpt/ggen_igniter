defmodule GgenIgniter.PendingActuation do
  @moduledoc """
  The reconciliation pipeline's real intermediate representation: what the
  `:render`/`:plan` phase of `GgenIgniter.Reactors.ReconcileReactor` actually
  produces is NOT a bare rendered-text string -- it is a `%PendingActuation{}`
  per intended output, describing the FULL intended delta (identity, prior
  vs. desired content hash, the exact operation, ownership, provenance, and
  how to revert it) so the `:admit` step can reason about (and refuse) the
  entire planned change set BEFORE a single byte is written, and the
  `:actuate` step can execute each item by its `operation` field directly
  instead of re-deriving "create vs. replace vs. delete" from scratch.

  This mirrors the real Rust ggen's own `PendingWrite`/`SyncReport` IR
  (`~/ggen/crates/ggen-engine/src/sync.rs:167-171`): the render phase there
  is likewise a real deferred-actuation planner, not merely a text
  templater. Same discipline, ported to this pipeline's own vocabulary
  (`GgenIgniter.Actuate`'s real `outcome()` values: `:written`/`:unchanged`/
  `:skipped_exists`/`:skipped_match`/`:injected`, and
  `GgenIgniter.Manifest`'s real `(template, out_template)` recipe/ownership
  model).

  ## Fields (conceptual IR -- what `:admit` reasons about)

    * `logical_id` -- a stable identity for this ONE intended output across
      runs. Composed by reusing `GgenIgniter.Manifest.recipe_key/2` (the
      `(template_path, out_template)` "recipe" identity Manifest already
      uses) plus the run's own resolved `target` path -- see
      `logical_id/3`. For the SAME row across successive runs (the common,
      unchanged-identity case), this is stable; a real ontology rename that
      changes the resolved path produces a genuinely new `logical_id`,
      exactly mirroring the honest limit `GgenIgniter.Manifest`'s own
      moduledoc already discloses for its `outputs` map (a rename is a new
      path, not a mutation of the old one).
    * `target` -- the real resolved output path this run intends to
      create/replace/inject/delete. `nil` only for `operation: :eval` (per
      `GgenIgniter.Manifest`'s own moduledoc: nothing is ever written to
      disk under `mode: eval`, so there is no path to reconcile).
    * `previous_hash` -- `GgenIgniter.Manifest.hash_content/1` of `target`'s
      CURRENT real on-disk content, or `nil` if `target` does not exist (or
      is `nil`, i.e. `:eval`).
    * `desired_hash` -- `GgenIgniter.Manifest.hash_content/1` of the content
      this run wants at `target` (the freshly-rendered/eval'd string), or
      `nil` for `operation: :delete` (nothing is desired there any more).
    * `operation` -- one of `:create | :replace | :inject | :delete | :eval`,
      DERIVED (never guessed) from real existence + the frontmatter/mode
      that produced this item -- see `for_file/6` and `for_delete/3`.
      `:inject` is declared in this type for forward compatibility with a
      future `inject: true` frontmatter pass through this Reactor pipeline,
      the same honest "not yet produced by this bounded slice" disclosure
      `GgenIgniter.Reconcile`'s own moduledoc already uses for its own
      deliberately-bounded scope -- `GgenIgniter.Reactors.ReconcileReactor`
      never constructs an `:inject` pending item today.
    * `ownership` -- whether THIS pack's manifest entry currently (i.e.
      BEFORE this run's actuation) already lists `target` as one of its own
      outputs, straight from `GgenIgniter.Manifest.output_paths/1` -- never
      re-derived by guesswork. Always `false` for `operation: :eval` (never
      tracked, per Manifest's own documented exclusion) and always `true`
      for a real `operation: :delete` stale-prune candidate (only paths a
      recipe's OWN manifest entry previously recorded are ever stale-prune
      candidates -- see `GgenIgniter.Manifest.stale_paths/2`).
    * `semantic_source` -- a plain map naming the real ontology/query/
      template identity that produced this item (`ontology_path`,
      `template_path`, `out_template`, `recipe_key`, and, for `:eval`, the
      real EEx `bindings` the eval'd code may reference -- see
      `GgenIgniter.Actuate.eval_code!/2`).
    * `compensation_data` -- exactly what `:actuate`'s real revert logic
      needs to undo THIS ONE item: `{:previous_content, bytes}` (the real
      bytes `target` held before this run, re-writable verbatim) when
      `target` existed, or the literal atom `:did_not_exist` when it did
      not (revert = delete it back out).

  ## One field beyond the conceptual list, disclosed here rather than smuggled in

  `desired_content` (real `binary()`) also rides on this struct. The four
  conceptual fields above (`previous_hash`/`desired_hash`/`operation`/
  `ownership`) are what ADMISSION reasons about; but a hash is one-way --
  `:actuate` cannot recover the actual bytes to write from `desired_hash`
  alone, and re-rendering at actuate-time would be exactly the kind of
  re-derivation this refactor exists to eliminate (`:actuate` must consume
  the plan directly, per the architectural request this module implements).
  So the real rendered/eval'd content this run wants travels with the item
  it belongs to, same struct, same plan, admitted as one unit.
  """

  alias GgenIgniter.Manifest

  @type operation :: :create | :replace | :inject | :delete | :eval
  @type compensation_data :: {:previous_content, binary()} | :did_not_exist

  @type t :: %__MODULE__{
          logical_id: String.t(),
          target: String.t() | nil,
          previous_hash: String.t() | nil,
          desired_hash: String.t() | nil,
          desired_content: binary() | nil,
          operation: operation(),
          ownership: boolean(),
          semantic_source: map(),
          compensation_data: compensation_data()
        }

  @enforce_keys [:logical_id, :operation, :ownership, :semantic_source, :compensation_data]
  defstruct logical_id: nil,
            target: nil,
            previous_hash: nil,
            desired_hash: nil,
            desired_content: nil,
            operation: nil,
            ownership: false,
            semantic_source: %{},
            compensation_data: :did_not_exist

  @doc """
  The stable identity for one resolved output of one `(template_path,
  out_template)` recipe -- reuses `GgenIgniter.Manifest.recipe_key/2` (the
  SAME key Manifest itself uses to look up prior-run entries) so this
  module never invents a second, parallel identity scheme.
  """
  @spec logical_id(String.t(), String.t(), String.t()) :: String.t()
  def logical_id(template_path, out_template, target)
      when is_binary(template_path) and is_binary(out_template) and is_binary(target) do
    Manifest.recipe_key(template_path, out_template) <> "::" <> target
  end

  @doc """
  Builds the real `%PendingActuation{}` for a `mode: file` (whole-file,
  non-inject) target: reads `target`'s REAL current on-disk content (if
  any) to compute `previous_hash`/`compensation_data`, hashes the real
  `desired_content`, and DERIVES `operation` from real existence alone
  (`:create` when `target` does not yet exist, `:replace` when it does --
  regardless of whether the content actually differs; that is exactly what
  lets an unchanged re-run still carry the intended `:create`/`:replace`
  operation type while `:actuate`'s real outcome comes back `:unchanged`).

  `ownership` is read straight from `old_entry` (the recipe's manifest entry
  as it stood BEFORE this run), via `GgenIgniter.Manifest.output_paths/1`.
  """
  @spec for_file(
          String.t(),
          binary(),
          String.t(),
          String.t(),
          Manifest.entry() | nil,
          map()
        ) :: t()
  def for_file(target, desired_content, template_path, out_template, old_entry, semantic_source)
      when is_binary(target) and is_binary(desired_content) do
    exists? = File.exists?(target)
    previous_content = if exists?, do: File.read!(target), else: nil

    %__MODULE__{
      logical_id: logical_id(template_path, out_template, target),
      target: target,
      previous_hash: previous_content && Manifest.hash_content(previous_content),
      desired_hash: Manifest.hash_content(desired_content),
      desired_content: desired_content,
      operation: if(exists?, do: :replace, else: :create),
      ownership: MapSet.member?(Manifest.output_paths(old_entry), target),
      semantic_source: semantic_source,
      compensation_data: compensation_for(previous_content)
    }
  end

  @doc """
  Builds the real `%PendingActuation{}` for a `mode: eval` target: nothing
  is ever written to disk (mirrors `GgenIgniter.Actuate.eval_code!/2` and
  `GgenIgniter.Manifest`'s own documented exclusion of `mode: eval` from
  reconciliation), so `target`/`previous_hash` are `nil` and `ownership` is
  always `false`. `desired_content` is the real Elixir source about to be
  evaluated; `semantic_source` should carry the real `bindings` keyword
  list `GgenIgniter.Actuate.eval_code!/2` needs at actuate time.
  """
  @spec for_eval(String.t(), String.t(), map()) :: t()
  def for_eval(code, template_path, semantic_source) when is_binary(code) do
    %__MODULE__{
      logical_id: template_path <> "=>eval",
      target: nil,
      previous_hash: nil,
      desired_hash: Manifest.hash_content(code),
      desired_content: code,
      operation: :eval,
      ownership: false,
      semantic_source: semantic_source,
      compensation_data: :did_not_exist
    }
  end

  @doc """
  Builds the real `%PendingActuation{}` for a stale-output prune candidate
  (`--on-stale prune`'s real deletion target): `target` is a path THIS
  recipe's manifest entry previously recorded but no longer produces this
  run (`GgenIgniter.Manifest.stale_paths/2`), so `ownership` is always
  `true` (only previously-owned paths are ever stale-prune candidates) and
  `desired_hash` is `nil` (nothing is desired there any more).
  `previous_hash`/`compensation_data` are read from `target`'s REAL current
  content, same as `for_file/6`.
  """
  @spec for_delete(String.t(), String.t(), String.t(), map()) :: t()
  def for_delete(target, template_path, out_template, semantic_source) when is_binary(target) do
    previous_content = if File.exists?(target), do: File.read!(target), else: nil

    %__MODULE__{
      logical_id: logical_id(template_path, out_template, target),
      target: target,
      previous_hash: previous_content && Manifest.hash_content(previous_content),
      desired_hash: nil,
      desired_content: nil,
      operation: :delete,
      ownership: true,
      semantic_source: semantic_source,
      compensation_data: compensation_for(previous_content)
    }
  end

  defp compensation_for(nil), do: :did_not_exist
  defp compensation_for(bytes) when is_binary(bytes), do: {:previous_content, bytes}

  @doc """
  Whether this item's plan already reflects "nothing will really change" --
  `previous_hash == desired_hash` (and both non-`nil`, so a fresh `:create`
  with nothing on disk yet is correctly NOT unchanged). Convenience for
  callers/tests reasoning about the plan before `:actuate` runs; does not
  itself touch disk.
  """
  @spec plan_unchanged?(t()) :: boolean()
  def plan_unchanged?(%__MODULE__{previous_hash: h, desired_hash: h}) when not is_nil(h), do: true
  def plan_unchanged?(%__MODULE__{}), do: false
end
