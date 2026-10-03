defmodule Mix.Tasks.SemanticJira.AdmitCandidates do
  @shortdoc "Admit or refuse JSONL Semantic Jira work-order candidates, one verdict per line"

  @moduledoc """
  Reads work-order CANDIDATES (one JSON object per line) and prints one
  verdict per non-blank line:

      mix semantic_jira.admit_candidates --candidates PATH [--authority-graph PATH] \\
        [--epoch-manifest PATH] [--sovereign-keys PATH]

  Each candidate is admitted only when ALL gates pass:

    1. `GgenIgniter.SemanticJira.admit_work_order/1` (shape, subject SHA,
       standing, required relations, `origin_authority` is an IRI); and
    2. its `origin_authority` RESOLVES to an admitted authority in the pinned
       authority index (`GgenIgniter.SemanticJira.Authority.index_from/1`): a
       node typed `sj:StrategicObjective`/`sj:GoalCheckpoint`, not prose,
       whose `sj:admissionDigest` recomputes. A prose origin never admits.

  Before either gate, the candidate line is refused when it claims what only
  receipts may confer (`candidate_bounds/1`):

    * `standing` other than `"UNKNOWN"` -- a candidate enters at UNKNOWN;
      standing is derived from receipts, never stored as a literal
      (`{:refused_candidate, {:literal_standing, s}}`);
    * `authority_requirement` other than `"NONE"` or `"SOVEREIGN"`, or an
      `evidence_ceiling` that is not a string or names an actuation in ANY
      token -- the value is split on every non-alphanumeric character (so
      `"DO/MERGE"`, `"merge-to-main"`, `"\\tdo\\n"` are each tokenized) and a
      token is refused when it is `DO`, `EXECUTE`, or begins with `ACTUAT`,
      `MERGE`, `PUBLISH`, `DEPLOY`, `PUSH`, `RELEASE` (any case).
      Evidence-ladder values (`SPECIFIED`, `IMPLEMENTED_UNVERIFIED`,
      `EXECUTED_VERIFIED`, `LOCAL_RUN`, `repository-local`, `CONSTRUCT`) name
      evidence, not actuation, and pass. The ceiling is at most CONSTRUCT
      (`{:refused_candidate, {:ceiling_exceeds_construct, field, value}}`).
      `"SOVEREIGN"` is admitted as a REQUIREMENT literal only -- ceilings stay
      at most CONSTRUCT for every order; a SOVEREIGN requirement demands the
      multi-party sovereign lease (see the gate below).

  Gate 3, the sovereign ceiling gate: a candidate with
  `authority_requirement: "SOVEREIGN"` (the kind-0x04 shape-evolution class)
  must carry a `sovereign_lease` object that
  `GgenIgniter.SemanticJira.SovereignLease.admit/3` admits against the CURRENT
  canonical pack ontology digest (sha256 of
  `priv/ggen/semantic-jira-pack/ontology.ttl`) and the public keys passed as
  `--sovereign-keys PATH` (a JSON object mapping signer identity to lowercase
  hex Ed25519 public key). A SOVEREIGN candidate without a lease is refused
  `{:refused_candidate, {:sovereign_lease_required, detail}}` and printed
  `REFUSED:SOVEREIGN_LEASE_REQUIRED`; a lease that fails to admit (bad or
  short signature set, unchanged ontology digest) is refused
  `{:refused_candidate, {:sovereign_lease_invalid, detail}}` and printed
  `REFUSED:SOVEREIGN_LEASE_INVALID`. Fail closed: an unreadable ontology file
  or a missing/unreadable keys file refuses every SOVEREIGN candidate
  (`:pack_ontology_digest_unavailable` / `:sovereign_keys_unavailable`).
  Candidates without a SOVEREIGN requirement are byte-identical to a run
  without the gate.

  Gate 4, opt-in exactly like git ground truth: a candidate carrying a
  nonempty `"epoch"` value is judged by the epoch admission gate
  (`GgenIgniter.SemanticJira.EpochPlan.check/2`) against the stamped
  watermark passed as `--epoch-manifest PATH` (a
  `.ggen_igniter/epoch/<epoch>/watermark.json`). An epoch candidate whose
  plan touches a stamped pre-epoch implementation path without a
  fresh-manufacture plan is refused `REFUSED:EPOCH_LEGACY_EDIT`; an
  implementation-plane touch with no manufacture plan is
  `REFUSED:EPOCH_UNATTRIBUTED_IMPLEMENTATION`; a pre-epoch artifact named as
  a source without a regeneration plan is
  `REFUSED:EPOCH_PLAN_REUSES_PRE_WATERMARK_ARTIFACT`; an epoch candidate
  with the flag missing or the manifest unreadable is
  `REFUSED:EPOCH_WATERMARK_UNAVAILABLE` (fail closed). Candidates WITHOUT an
  `"epoch"` value are byte-identical to a run without the option -- the
  canonical fabric set still manufactures unchanged.

  Within one batch, a later line whose `identity`, `replay_identity`, or
  admitted `work_order_digest` repeats an earlier ADMITTED line is refused
  (`{:refused_candidate, {:duplicate, field, first_line}}`): one candidate,
  one admission.

  Output, one line per candidate line, in input order:

      admitted <line> <identity> origin=<iri> origin_digest=<digest> work_order_digest=<digest>
      refused <line> <identity|-> <typed reason>

  followed by one summary line `summary admitted=<n> refused=<n>`.

  Exit `0` when every line was judged (admitted or refused -- a refusal is a
  verdict, not a failure), `2` for an invalid invocation or an unreadable
  candidates file, `1` when the authority index is unavailable (fail closed:
  nothing is admitted). Authority NONE: this task only SELECTs; it writes
  nothing and actuates nothing.
  """

  use Mix.Task

  alias GgenIgniter.Digest
  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.Authority
  alias GgenIgniter.SemanticJira.EpochPlan
  alias GgenIgniter.SemanticJira.SovereignLease

  @pack_ontology "priv/ggen/semantic-jira-pack/ontology.ttl"

  @impl Mix.Task
  def run(args) do
    {opts, _rest, invalid} =
      OptionParser.parse(args,
        strict: [
          candidates: :string,
          authority_graph: :string,
          epoch_manifest: :string,
          sovereign_keys: :string
        ]
      )

    path = opts[:candidates]

    if invalid != [] or is_nil(path) do
      Mix.shell().error(
        "usage: mix semantic_jira.admit_candidates --candidates PATH [--authority-graph PATH] [--epoch-manifest PATH] [--sovereign-keys PATH]"
      )

      exit({:shutdown, 2})
    end

    judge_file(path, opts[:authority_graph], opts[:epoch_manifest], opts[:sovereign_keys])
  end

  defp judge_file(path, authority_graph, epoch_manifest, sovereign_keys_path) do
    lines =
      case File.read(path) do
        {:ok, bytes} ->
          String.split(bytes, "\n")

        {:error, reason} ->
          Mix.shell().error("refused: cannot read #{path}: #{inspect(reason)}")
          exit({:shutdown, 2})
      end

    index_opts = if authority_graph, do: [authority: authority_graph], else: []

    index =
      case Authority.index_from(index_opts) do
        {:ok, index} ->
          index

        {:error, reason} ->
          Mix.shell().error("refused: authority index unavailable: #{inspect(reason)}")
          exit({:shutdown, 1})
      end

    watermark = epoch_watermark(epoch_manifest)
    sovereign = sovereign_opts(sovereign_keys_path)

    verdicts =
      lines
      |> Enum.with_index(1)
      |> Enum.reject(fn {line, _n} -> String.trim(line) == "" end)
      |> Enum.map(fn {line, n} -> {n, judge_line(line, index, watermark, sovereign)} end)
      |> dedupe()

    Enum.each(verdicts, fn {n, verdict} -> Mix.shell().info(format(n, verdict)) end)

    admitted = Enum.count(verdicts, fn {_n, v} -> match?({:admitted, _, _}, v) end)

    Mix.shell().info("summary admitted=#{admitted} refused=#{length(verdicts) - admitted}")
  end

  # Loaded once per run, lazily: the pack ontology digest is read even when no
  # SOVEREIGN candidate appears (it is one small file read), but the public
  # keys file is only required to be READABLE -- an unreadable either is not a
  # run failure, it is the fail-closed refusal of every SOVEREIGN candidate
  # (`:pack_ontology_digest_unavailable` / `:sovereign_keys_unavailable`).
  defp sovereign_opts(nil), do: sovereign_opts([])

  defp sovereign_opts(keys_path) do
    ontology_digest =
      case File.read(Path.expand(@pack_ontology, File.cwd!())) do
        {:ok, bytes} -> Digest.hex(bytes)
        {:error, _} -> nil
      end

    public_keys =
      with path when is_binary(path) <- keys_path,
           {:ok, bytes} <- File.read(path),
           {:ok, json} when is_map(json) <- Jason.decode(bytes) do
        Map.new(json, fn {signer, hex} ->
          {signer, Base.decode16!(String.upcase(hex), padding: false)}
        end)
      else
        _ -> nil
      end

    [ontology_digest: ontology_digest, public_keys: public_keys]
  end

  # Loaded once per run, lazily: a run whose candidates never carry an
  # "epoch" value never needs the manifest (and a missing one must not turn
  # a no-epoch run into a failure). `nil` watermark + an epoch candidate is
  # the fail-closed refusal inside EpochPlan.check/2, so the unavailable
  # case needs no special path here.
  defp epoch_watermark(nil), do: nil

  defp epoch_watermark(path) do
    case File.read(path) do
      {:ok, bytes} ->
        case Jason.decode(bytes) do
          {:ok, watermark} when is_map(watermark) -> watermark
          _ -> nil
        end

      {:error, _} ->
        nil
    end
  end

  @doc false
  @spec judge_line(String.t(), Authority.index(), map() | nil, keyword()) ::
          {:admitted, map(), String.t()} | {:refused, String.t() | nil, term()}
  def judge_line(line, index, watermark \\ nil, sovereign \\ []) do
    case Jason.decode(line) do
      {:ok, candidate} when is_map(candidate) ->
        identity = identity_of(candidate)

        with :ok <- epoch_gate(candidate, watermark),
             :ok <- candidate_bounds(candidate),
             {:ok, admitted} <- SemanticJira.admit_work_order(candidate),
             :ok <- sovereign_gate(candidate, sovereign),
             {:ok, origin_digest} <- Authority.resolve(index, admitted["origin_authority"]) do
          {:admitted, admitted, origin_digest}
        else
          {:error, {:refused_epoch_plan, code}} when is_atom(code) ->
            {:refused, identity, EpochPlan.refusal_code_string(code)}

          {:error, reason} ->
            {:refused, identity, reason}
        end

      {:ok, other} ->
        {:refused, nil, {:refused_work_order, {:expected_json_object, type_of(other)}}}

      {:error, %Jason.DecodeError{position: position}} ->
        {:refused, nil, {:refused_work_order, {:invalid_json, position}}}
    end
  end

  # The sovereign ceiling gate: only SOVEREIGN-requirement candidates are
  # judged here; every other candidate passes byte-identically. Fail closed
  # on unavailable digest or keys.
  defp sovereign_gate(candidate, sovereign) do
    requirement = Map.get(candidate, "authority_requirement", "NONE")

    if requirement != "SOVEREIGN" do
      :ok
    else
      do_sovereign_gate(Map.get(candidate, "sovereign_lease"), sovereign)
    end
  end

  defp do_sovereign_gate(lease, _sovereign) when not is_map(lease) do
    {:error, {:refused_candidate, {:sovereign_lease_required, :no_sovereign_lease}}}
  end

  defp do_sovereign_gate(lease, sovereign) do
    digest = Keyword.get(sovereign, :ontology_digest)
    keys = Keyword.get(sovereign, :public_keys)

    cond do
      not is_binary(digest) ->
        {:error,
         {:refused_candidate, {:sovereign_lease_invalid, :pack_ontology_digest_unavailable}}}

      not is_map(keys) ->
        {:error, {:refused_candidate, {:sovereign_lease_invalid, :sovereign_keys_unavailable}}}

      true ->
        case SovereignLease.admit(lease, digest, public_keys: keys) do
          {:ok, _admitted} ->
            :ok

          {:error, {:refused_sovereign, reason}} ->
            {:error, {:refused_candidate, {:sovereign_lease_invalid, reason}}}
        end
    end
  end

  # The epoch gate sits BEFORE the existing gates: a plan that carries
  # pre-epoch implementation is refused for the epoch reason first. For a
  # candidate without an "epoch" value EpochPlan.check/2 is :ok, so the
  # chain -- and every printed line -- is byte-identical to a run without
  # the gate.
  defp epoch_gate(candidate, watermark), do: EpochPlan.check(candidate, watermark)

  # Whole-token actuations, and actuation roots matched as token prefixes
  # (MERGED, PUSHED, DEPLOYMENT, ACTUATE, ACTUATION, ...). EXECUTE is exact:
  # EXECUTED (as in EXECUTED_VERIFIED) is evidence that tests ran, not a DO.
  @actuation_tokens ~w(DO EXECUTE)
  @actuation_roots ~w(ACTUAT MERGE PUBLISH DEPLOY PUSH RELEASE)

  @doc false
  @spec candidate_bounds(map()) :: :ok | {:error, term()}
  def candidate_bounds(candidate) do
    standing = Map.get(candidate, "standing", "UNKNOWN")
    requirement = Map.get(candidate, "authority_requirement", "NONE")
    ceiling = Map.get(candidate, "evidence_ceiling")

    cond do
      standing != "UNKNOWN" ->
        {:error, {:refused_candidate, {:literal_standing, standing}}}

      # SOVEREIGN is a REQUIREMENT literal, not a ceiling: ceilings stay at
      # most CONSTRUCT for every order, and the SOVEREIGN requirement is
      # enforced by the sovereign ceiling gate (the lease), never by widening
      # any ceiling.
      requirement not in ["NONE", "SOVEREIGN"] ->
        {:error,
         {:refused_candidate, {:ceiling_exceeds_construct, "authority_requirement", requirement}}}

      not is_nil(ceiling) and not is_binary(ceiling) ->
        {:error, {:refused_candidate, {:ceiling_exceeds_construct, "evidence_ceiling", ceiling}}}

      is_binary(ceiling) and names_actuation?(ceiling) ->
        {:error, {:refused_candidate, {:ceiling_exceeds_construct, "evidence_ceiling", ceiling}}}

      true ->
        :ok
    end
  end

  @doc false
  @spec names_actuation?(String.t()) :: boolean()
  def names_actuation?(value) when is_binary(value) do
    value
    |> String.upcase()
    |> String.split(~r/[^A-Z0-9]+/u, trim: true)
    |> Enum.any?(fn token ->
      token in @actuation_tokens or Enum.any?(@actuation_roots, &String.starts_with?(token, &1))
    end)
  end

  # One candidate, one admission: a later admitted line that repeats an
  # earlier admitted line's identity, replay_identity, or work_order_digest is
  # refused, naming the field and the first line.
  defp dedupe(verdicts) do
    {out, _seen} =
      Enum.map_reduce(verdicts, %{}, fn
        {n, {:admitted, wo, _digest}} = verdict, seen ->
          keys = for f <- ~w(identity replay_identity work_order_digest), do: {f, wo[f]}

          case Enum.find(keys, &Map.has_key?(seen, &1)) do
            nil ->
              {verdict, Enum.reduce(keys, seen, &Map.put(&2, &1, n))}

            {field, _} = key ->
              {{n,
                {:refused, wo["identity"], {:refused_candidate, {:duplicate, field, seen[key]}}}},
               seen}
          end

        other, seen ->
          {other, seen}
      end)

    out
  end

  defp identity_of(%{"identity" => identity}) when is_binary(identity), do: identity
  defp identity_of(_), do: nil

  defp type_of(value) when is_list(value), do: :array
  defp type_of(value) when is_binary(value), do: :string
  defp type_of(value) when is_number(value), do: :number
  defp type_of(nil), do: :null
  defp type_of(_), do: :other

  defp detail_string(detail) when is_binary(detail), do: detail
  defp detail_string(detail), do: inspect(detail)

  defp format(n, {:admitted, work_order, origin_digest}) do
    "admitted #{n} #{work_order["identity"]} origin=#{work_order["origin_authority"]} " <>
      "origin_digest=#{origin_digest} work_order_digest=#{work_order["work_order_digest"]}"
  end

  # Sovereign ceiling refusals keep the typed tuple on judge_line's return
  # and print the canonical registry codes:
  #   REFUSED:SOVEREIGN_LEASE_REQUIRED <detail>
  #   REFUSED:SOVEREIGN_LEASE_INVALID <detail>
  defp format(n, {:refused, identity, {:refused_candidate, {:sovereign_lease_required, detail}}}) do
    "refused #{n} #{identity || "-"} REFUSED:SOVEREIGN_LEASE_REQUIRED #{detail_string(detail)}"
  end

  defp format(n, {:refused, identity, {:refused_candidate, {:sovereign_lease_invalid, detail}}}) do
    "refused #{n} #{identity || "-"} REFUSED:SOVEREIGN_LEASE_INVALID #{detail_string(detail)}"
  end

  # Epoch refusals arrive as canonical `REFUSED:EPOCH_*` strings and print
  # bare; the clause is additive and cannot change a tuple-reason line's shape.
  defp format(n, {:refused, identity, reason}) when is_binary(reason) do
    "refused #{n} #{identity || "-"} #{reason}"
  end

  defp format(n, {:refused, identity, reason}) do
    "refused #{n} #{identity || "-"} #{inspect(reason)}"
  end
end
