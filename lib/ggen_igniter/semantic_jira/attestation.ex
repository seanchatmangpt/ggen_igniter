defmodule GgenIgniter.SemanticJira.Attestation do
  @moduledoc """
  Proof-carrying admission decisions (DfCM composition C11): an in-toto
  Statement v1 for every transition admitted by
  `GgenIgniter.SemanticJira.Reconciler.reconcile/4`, and the offline verifier
  that replays the admission itself rather than trusting it.

  - `statement/1` builds the Statement from a `Reconciler.decide/3` decision:
    * `subject[0]` is the admitted WorkOrder: `name` `sj:WorkOrder/<identity>`,
      `digest.sha256` = the hex of its `work_order_digest`
      (`SemanticJira.admit_work_order/1`).
    * `subject[1]` is the exact subject commit: `name` = the repository,
      `digest.gitCommit` = the receipt's `candidate_sha`, else the WorkOrder's
      `base_sha`.
    * `predicateType` is `https://chatmangpt.com/sj/admission/v1` (JSON Schema
      `priv/schema/sj_admission.schema.json`). The predicate carries the
      decision, the courts, falsifiers and acceptance results the kernel
      checked, the `SemanticJira.promote/3` checks, the authority (granted
      `NONE`, requirement, prepared authority receipt), the standing
      transition (derived from the receipt digest), and the full receipt.
  - `render/1` projects the Statement to JSON through the
    `semantic-jira-pack` template `runtime-templates/admission_statement.json.eex`.
    Object keys are sorted recursively, so the same decision always renders
    byte-identical JSON.
  - `emit/3` writes `<stem>.intoto.json` next to the event file `<stem>.json`
    (`TransitionLog.stem/1`) through a temp file and rename. An existing
    statement file is never rewritten. `ensure/5` re-emits a missing
    statement for an already-recorded receipt by replaying `Reconciler.decide/3`
    over the log prefix before its event (this covers a crash between the
    append and the emission, and logs written before C11).
  - `verify/3` is the offline verifier. It needs no network, key or producer
    state: only the Statement, the WorkOrder and the transition log. It
    checks the in-toto v1 structural rules (the checks of in-toto/attestation
    `go/v1` `Statement.Validate` and `ResourceDescriptor.Validate`) and the
    predicate type. Then it replays: the embedded receipt must be the logged
    one (matched by `receipt_digest`), and `Reconciler.decide/3` over the log
    prefix before that event must re-derive the same `event_digest`. Finally
    the rebuilt Statement must equal the given one in `subject` and
    `predicate`. Any difference is a typed
    `{:error, {:refused_attestation, reason}}`.

  Integrity comes from replay against the append-only log, not from a
  signature. The Statement is not wrapped in a DSSE envelope and is not signed,
  because this kernel holds no key material and no lease (authority `NONE`).
  DSSE signing by a leased signer is disclosed follow-on work. Refused
  transitions emit no Statement. A concurrent writer racing a transition of the
  same identity can make the logged `from` differ from the one the log prefix
  re-derives; `verify/3` then refuses with `:event_not_rederived` instead of
  admitting an unreplayable decision.
  """

  alias GgenIgniter.{Render, SemanticA2A, SemanticJira}
  alias GgenIgniter.SemanticJira.{Reconciler, TransitionLog}

  @statement_type "https://in-toto.io/Statement/v1"
  @predicate_type "https://chatmangpt.com/sj/admission/v1"
  @kernel "GgenIgniter.SemanticJira.Reconciler.decide/3"
  @suffix ".intoto.json"
  @template "admission_statement.json.eex"

  # Lowercase-hex lengths for the DigestSet algorithms whose encoding in-toto
  # fixes (spec/v1/digest_set.md; byte sizes from go/v1/resource_descriptor.go).
  @hex_lengths %{
    "md5" => [32],
    "sha1" => [40],
    "sha224" => [56],
    "sha512_224" => [56],
    "sha3_224" => [56],
    "sha256" => [64],
    "sha512_256" => [64],
    "sha3_256" => [64],
    "dirHash" => [64],
    "sha384" => [96],
    "sha3_384" => [96],
    "sha512" => [128],
    "sha3_512" => [128],
    "gitCommit" => [40, 64],
    "gitTree" => [40, 64],
    "gitBlob" => [40, 64],
    "gitTag" => [40, 64]
  }

  @type refusal :: {:error, {:refused_attestation, term()}}

  @doc "The in-toto Statement type URI emitted here."
  @spec statement_type() :: String.t()
  def statement_type, do: @statement_type

  @doc "The Semantic Jira admission predicate type URI."
  @spec predicate_type() :: String.t()
  def predicate_type, do: @predicate_type

  @doc "Path of the Statement kept next to `event`'s file in the log `dir`."
  @spec path(Path.t(), map()) :: Path.t()
  def path(dir, event), do: Path.join(dir, TransitionLog.stem(event) <> @suffix)

  @doc "The in-toto subjects of an admitted WorkOrder at `subject_sha`."
  @spec subjects(map(), String.t()) :: [map()]
  def subjects(%{"work_order_digest" => "sha256:" <> hex} = admitted, subject_sha) do
    [
      %{"name" => "sj:WorkOrder/" <> admitted["identity"], "digest" => %{"sha256" => hex}},
      %{"name" => admitted["repository"], "digest" => %{"gitCommit" => subject_sha}}
    ]
  end

  @doc "Builds the Statement (JSON-safe map) for a `Reconciler.decide/3` decision."
  @spec statement(map()) :: map()
  def statement(%{
        "admitted" => admitted,
        "definition_digest" => definition_digest,
        "receipt" => receipt,
        "intent" => intent,
        "event" => event
      }) do
    evidence = receipt["evidence"] || %{}

    json_safe(%{
      "_type" => @statement_type,
      "subject" => subjects(admitted, receipt["candidate_sha"] || admitted["base_sha"]),
      "predicateType" => @predicate_type,
      "predicate" => %{
        "decision" => "ADMITTED",
        "kernel" => @kernel,
        "work_order" => %{
          "identity" => admitted["identity"],
          "repository" => admitted["repository"],
          "subject" => admitted["subject"],
          "base_sha" => admitted["base_sha"],
          "candidate_sha" => admitted["candidate_sha"],
          "definition_digest" => definition_digest,
          "work_order_digest" => admitted["work_order_digest"],
          "snapshot_digest" => receipt["snapshot_digest"]
        },
        "transition" => %{
          "from" => event["from"],
          "to" => event["to"],
          "transition_digest" => intent["transition_digest"],
          "event_digest" => SemanticJira.digest(event),
          "receipt_digest" => event["receipt_digest"]
        },
        "courts" =>
          Enum.map(
            admitted["required_courts"],
            &%{"court" => &1, "passed" => get_in(evidence, ["court_results", &1, "passed"])}
          ),
        "falsifiers" =>
          Enum.map(
            admitted["falsifiers"],
            &%{"falsifier" => &1, "result" => get_in(evidence, ["falsifier_results", &1])}
          ),
        "acceptance" =>
          Enum.map(
            admitted["acceptance"],
            &%{"criterion" => &1, "passed" => get_in(evidence, ["acceptance_results", &1])}
          ),
        "checks" => intent["checks"],
        "authority" => %{
          "granted" => "NONE",
          "requirement" => admitted["authority_requirement"],
          "authority_receipt" => evidence["authority_receipt"]
        },
        "standing" => %{
          "from" => event["from"],
          "to" => event["to"],
          "derived_from" => event["receipt_digest"]
        },
        "receipt" => receipt
      }
    })
  end

  @doc "Renders a Statement as JSON through the pack's `admission_statement.json.eex`."
  @spec render(map()) :: String.t()
  def render(statement) when is_map(statement) do
    bindings = [
      type_json: encode(statement["_type"]),
      subject_json: encode(statement["subject"]),
      predicate_type_json: encode(statement["predicateType"]),
      predicate_json: encode(statement["predicate"])
    ]

    [SemanticA2A.pack_dir(), "runtime-templates", @template]
    |> Path.join()
    |> File.read!()
    |> Render.render(bindings)
  end

  @doc "Writes the Statement of `decision` next to the appended `event` (never rewrites)."
  @spec emit(Path.t(), map(), map()) :: :ok
  def emit(dir, event, decision) do
    target = path(dir, event)

    if File.exists?(target) do
      :ok
    else
      tmp = target <> ".#{System.unique_integer([:positive])}.tmp"
      File.write!(tmp, render(statement(decision)))
      File.rename!(tmp, target)
      :ok
    end
  end

  @doc """
  Re-emits the Statement of an already-recorded `event` when it is missing, by
  replaying `Reconciler.decide/3` over the log prefix before the event.
  """
  @spec ensure(Path.t(), map(), map(), map(), [map()]) :: :ok | refusal()
  def ensure(dir, event, work_order, receipt, events) do
    if File.exists?(path(dir, event)) do
      :ok
    else
      with {:ok, decision} <- replay(work_order, receipt, prefix(events, event)),
           :ok <- rederived(decision, event) do
        emit(dir, event, decision)
      end
    end
  end

  @doc "Reads and decodes the Statement stored next to `event` in the log `dir`."
  @spec read(Path.t(), map()) :: {:ok, map()} | {:error, term()}
  def read(dir, event) do
    with {:ok, body} <- File.read(path(dir, event)), do: Jason.decode(body)
  end

  @doc """
  Offline verifier: validates the Statement's in-toto v1 structure, then
  replays the admission from the WorkOrder and the transition log `events`
  and refuses any Statement whose subject or predicate does not re-derive.
  """
  @spec verify(map() | String.t(), map(), [map()]) :: {:ok, map()} | refusal()
  def verify(statement, work_order, events) when is_binary(statement) do
    case Jason.decode(statement) do
      {:ok, decoded} -> verify(decoded, work_order, events)
      {:error, _} -> refused(:not_json)
    end
  end

  def verify(statement, work_order, events) when is_map(statement) and is_list(events) do
    with :ok <- in_toto_v1(statement),
         :ok <-
           check(
             statement["predicateType"] == @predicate_type,
             {:unknown_predicate_type, statement["predicateType"]}
           ),
         {:ok, receipt} <- embedded_receipt(statement),
         {:ok, event} <- logged_event(events, receipt),
         {:ok, decision} <- replay(work_order, receipt, prefix(events, event)),
         :ok <- rederived(decision, event),
         expected = statement(decision),
         :ok <- same(:subject_mismatch, expected["subject"], statement["subject"]),
         :ok <- same(:predicate_mismatch, expected["predicate"], statement["predicate"]) do
      {:ok,
       %{
         "decision" => "ADMITTED",
         "subject" => expected["subject"],
         "event_digest" => event["event_digest"],
         "seq" => event["seq"]
       }}
    end
  end

  # -- in-toto Statement v1 structure ------------------------------------------

  defp in_toto_v1(%{"_type" => @statement_type} = statement) do
    cond do
      not match?([_ | _], statement["subject"]) ->
        refused(:subject_required)

      not Enum.all?(statement["subject"], &subject?/1) ->
        refused(:invalid_subject)

      not (is_binary(statement["predicateType"]) and statement["predicateType"] != "") ->
        refused(:predicate_type_required)

      not is_map(statement["predicate"]) ->
        refused(:predicate_required)

      true ->
        :ok
    end
  end

  defp in_toto_v1(%{"_type" => type}), do: refused({:invalid_statement_type, type})
  defp in_toto_v1(_), do: refused(:invalid_statement_type)

  defp subject?(%{"digest" => digest} = subject) when is_map(digest) and map_size(digest) > 0 do
    (is_nil(subject["name"]) or is_binary(subject["name"])) and
      Enum.all?(digest, fn {algorithm, value} -> digest_value?(algorithm, value) end)
  end

  defp subject?(_), do: false

  defp digest_value?(algorithm, value) when is_binary(value) do
    case Map.fetch(@hex_lengths, algorithm) do
      {:ok, lengths} -> String.length(value) in lengths and Regex.match?(~r/\A[0-9a-f]+\z/, value)
      :error -> true
    end
  end

  defp digest_value?(_, _), do: false

  # -- replay -----------------------------------------------------------------

  defp embedded_receipt(%{"predicate" => %{"receipt" => receipt}}) when is_map(receipt),
    do: {:ok, receipt}

  defp embedded_receipt(_), do: refused(:receipt_missing)

  defp logged_event(events, receipt) do
    digest = SemanticJira.digest(receipt)

    case Enum.find(events, &(&1["receipt_digest"] == digest)) do
      nil -> refused({:receipt_not_logged, digest})
      event -> {:ok, event}
    end
  end

  defp prefix(events, %{"seq" => seq}), do: Enum.filter(events, &((&1["seq"] || 0) < seq))

  defp replay(work_order, receipt, events) do
    case Reconciler.decide(work_order, receipt, events) do
      {:ok, decision} -> {:ok, decision}
      {:error, {:refused, reason}} -> refused({:replay_refused, reason})
    end
  end

  defp rederived(decision, event) do
    check(SemanticJira.digest(decision["event"]) == event["event_digest"], :event_not_rederived)
  end

  defp same(_tag, value, value), do: :ok

  defp same(tag, expected, given) when is_map(expected) and is_map(given) do
    keys =
      (Map.keys(expected) ++ Map.keys(given))
      |> Enum.uniq()
      |> Enum.filter(&(Map.get(expected, &1) != Map.get(given, &1)))
      |> Enum.sort()

    refused({tag, keys})
  end

  defp same(tag, expected, given) when is_list(expected) and is_list(given) do
    names =
      (expected -- given)
      |> Kernel.++(given -- expected)
      |> Enum.map(&if(is_map(&1), do: &1["name"], else: &1))
      |> Enum.uniq()

    refused({tag, names})
  end

  defp same(tag, _expected, _given), do: refused({tag, :shape})

  # -- helpers ------------------------------------------------------------------

  defp check(true, _), do: :ok
  defp check(_, reason), do: refused(reason)

  defp refused(reason), do: {:error, {:refused_attestation, reason}}

  defp json_safe(value), do: value |> Jason.encode!() |> Jason.decode!()

  defp encode(value), do: value |> ordered() |> Jason.encode!()

  defp ordered(value) when is_map(value) and not is_struct(value) do
    value
    |> Enum.map(fn {k, v} -> {to_string(k), ordered(v)} end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Jason.OrderedObject.new()
  end

  defp ordered(value) when is_list(value), do: Enum.map(value, &ordered/1)
  defp ordered(value), do: value
end
