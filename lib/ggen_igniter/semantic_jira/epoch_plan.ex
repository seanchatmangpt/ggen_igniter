defmodule GgenIgniter.SemanticJira.EpochPlan do
  alias GgenIgniter.Refusals

  @moduledoc """
  Admission-side epoch gate: refuses a WorkOrder candidate whose PLAN would
  carry pre-watermark implementation into a post-watermark epoch, before
  any construction happens.

  ## Why admission cannot be the whole law

  This gate sees the order's declared plan (`sj:planTouches`,
  `sj:manufacturePlan`, `sj:sourceArtifacts`) — it cannot prove the bytes a
  worker will actually write. `GgenIgniter.EpochFreshness.check` proves the
  tree afterwards; promotion requires both. What this gate buys is the
  cheap refusal direction: an order that says "modify `lib/foo.ex`" where
  `lib/foo.ex` is a stamped pre-epoch identity never reaches a coding
  worker at all.

  ## Opt-in, two levels (no-regression contract)

  The gate applies ONLY to candidates carrying a nonempty `"epoch"` value —
  the same two-level opt-in discipline as
  `GgenIgniter.SemanticJira.GitGroundTruth`: the candidate opts itself in,
  and the run supplies `--epoch-manifest PATH` naming the stamped
  `watermark.json`. An epoch-carrying candidate with no (or unreadable)
  manifest is refused `REFUSED:EPOCH_WATERMARK_UNAVAILABLE` — fail closed —
  while candidates without `"epoch"` behave byte-identically to a run
  without the gate.
  """

  @typedoc "One refusal code of the epoch plan gate."
  @type code ::
          :legacy_edit
          | :unattributed_implementation
          | :reuses_pre_watermark_artifact
          | :watermark_unavailable

  @fresh_plans ~w(generated residue)

  @doc """
  Judges one decoded candidate against a stamped watermark map (decoded
  `watermark.json`), or `nil` when no manifest is available.

  `:ok` when the gate does not apply (no `"epoch"`) or the plan is lawful;
  `{:error, {:refused_epoch_plan, code}}` otherwise. Violation precedence
  is the rule order below: legacy edit, then unattributed implementation,
  then pre-watermark source reuse.
  """
  @spec check(map(), map() | nil) :: :ok | {:error, {:refused_epoch_plan, code()}}
  def check(order, watermark)

  def check(%{"epoch" => epoch} = order, watermark) when is_binary(epoch) and epoch != "" do
    case watermark do
      nil ->
        {:error, {:refused_epoch_plan, :watermark_unavailable}}

      %{"files" => _} = watermark ->
        plan_touches = listify(order["plan_touches"])
        manufacture_plan = plan_map(order["manufacture_plan"])
        source_artifacts = listify(order["source_artifacts"])
        legacy_paths = MapSet.new(List.wrap(watermark["files"]), & &1["path"])
        matchers = impl_globs(watermark) |> Enum.map(&glob_matcher/1)

        cond do
          Enum.any?(plan_touches, &(&1 in legacy_paths and not fresh_plan?(&1, manufacture_plan))) ->
            {:error, {:refused_epoch_plan, :legacy_edit}}

          Enum.any?(plan_touches, fn path ->
            path not in legacy_paths and any_matcher?(matchers, path) and
                not fresh_plan?(path, manufacture_plan)
          end) ->
            {:error, {:refused_epoch_plan, :unattributed_implementation}}

          Enum.any?(
            source_artifacts,
            &(&1 in legacy_paths and not fresh_plan?(&1, manufacture_plan))
          ) ->
            {:error, {:refused_epoch_plan, :reuses_pre_watermark_artifact}}

          true ->
            :ok
        end

      _ ->
        {:error, {:refused_epoch_plan, :watermark_unavailable}}
    end
  end

  def check(_order, _watermark), do: :ok

  @doc "The typed refusal string a code renders as in the admit_candidates verdict line."
  @spec refusal_code_string(code()) :: String.t()
  def refusal_code_string(:legacy_edit), do: Refusals.format(:EPOCH_LEGACY_EDIT)

  def refusal_code_string(:unattributed_implementation),
    do: Refusals.format(:EPOCH_UNATTRIBUTED_IMPLEMENTATION)

  def refusal_code_string(:reuses_pre_watermark_artifact),
    do: Refusals.format(:EPOCH_PLAN_REUSES_PRE_WATERMARK_ARTIFACT)

  def refusal_code_string(:watermark_unavailable),
    do: Refusals.format(:EPOCH_WATERMARK_UNAVAILABLE)

  # -- plan normalization -------------------------------------------------------

  defp listify(nil), do: []
  defp listify(value) when is_binary(value), do: [value]
  defp listify(value) when is_list(value), do: Enum.filter(value, &is_binary/1)
  defp listify(_), do: []

  defp plan_map(value) when is_map(value), do: value
  defp plan_map(_), do: %{}

  defp fresh_plan?(path, manufacture_plan) do
    manufacture_plan[path] in @fresh_plans
  end

  # The watermark's implementation-plane glob set: the multi-plane
  # `implementation_globs` list when present, else the historical single
  # `implementation_glob`, UNION the current default set — the same
  # recorded-∪-default semantics the court applies
  # (`GgenIgniter.EpochFreshness.watermark_globs/1`, epoch_freshness.ex
  # "Judged planes" clause: `Enum.uniq(recorded_globs(watermark) ++
  # EpochWatermark.default_globs())`). A pre-multi-plane lib-only watermark
  # therefore still has its config/migration planes looked at at admission
  # (fail closed), so a plan line can never pass admission and then be
  # refused by `mix ggen_igniter.epoch.check` — no admission≠proof split.
  # The court and the admission gate must agree on which paths are implementation-plane,
  # so both speak the same dialect: `**` crosses directories (and matches
  # none — `lib/**/*.ex` includes `lib/foo.ex`), `*` stays within one, `?`
  # is one non-slash character.
  defp impl_globs(watermark) do
    recorded =
      case watermark do
        %{"implementation_globs" => globs} when is_list(globs) ->
          Enum.filter(globs, &is_binary/1)

        %{"implementation_glob" => glob} when is_binary(glob) ->
          [glob]

        _ ->
          []
      end

    Enum.uniq(recorded ++ GgenIgniter.EpochWatermark.default_globs())
  end

  defp any_matcher?(matchers, path), do: Enum.any?(matchers, & &1.(path))

  defp glob_matcher(nil), do: glob_matcher("lib/**/*.ex")

  defp glob_matcher(glob) when is_binary(glob) do
    regex = glob_regex(glob)

    fn path -> Regex.match?(regex, path) end
  end

  # Placeholders keep the three wildcard classes distinct through the
  # escape pass: `**/` first (so it is not eaten as `**` + `*`), then the
  # rest, then everything non-wildcard is regex-escaped verbatim.
  @dstar_slash "\u{E000}"
  @dstar "\u{E001}"
  @star "\u{E002}"
  @qmark "\u{E003}"

  defp glob_regex(glob) do
    source =
      glob
      |> String.replace("**/", @dstar_slash)
      |> String.replace("**", @dstar)
      |> String.replace("*", @star)
      |> String.replace("?", @qmark)
      |> String.graphemes()
      |> Enum.map_join(fn
        @dstar_slash -> "(?:.*/)?"
        @dstar -> ".*"
        @star -> "[^/]*"
        @qmark -> "[^/]"
        ch -> Regex.escape(ch)
      end)

    Regex.compile!("^" <> source <> "$")
  end
end
