defmodule GgenIgniter.SemanticJira.Bootstrap.Receipts do
  @moduledoc """
  Receipt side of the cold bootstrap (GC23-1): reads fleet R-schema receipts
  (`identity`, `authority`, `consequence`, `replay`, `standing`) from receipt
  directories, admits them structurally, links them to work orders and gates,
  and applies the exact-subject law (PR-006, ARD section 26 F5/F6).

  Admission (`check/1`) is the structural content of the fleet R schema --
  the v1 required fields (`identity`, `authority`, `consequence`, `replay`,
  `standing`; 40-hex subject/base SHAs; `authority.ceiling` in
  OBSERVE/SELECT/CONSTRUCT/DO; a non-empty replay command list with integer
  exits; the standing pattern; `broken_term` required for
  BLOCKED/BUILD_BROKEN/REFUSED), PLUS the fleet R v2 required keys
  (`work_order_id`, `origin_authority{grant,actor}` with an optional
  OBSERVE/SELECT/CONSTRUCT/DO ceiling, `provider{name}`,
  `provider_execution_id`), the extension-namespace rule (every top-level key
  outside the known set must match `^provider_ext\\.[a-z0-9][a-z0-9_.-]*$`
  and be an object), and the validator's semantic rule that an ALIVE receipt
  has no non-zero replay exit (`admission_vacuous`). A v1-only receipt (one
  carrying only the five v1 fields) refuses with the typed v2 reasons above --
  a string per missing key, never a crash. The fleet schema's promoted home
  is fleet-side (see docs/jira/v26.10.2 for its promoted home), which the
  bootstrap may not read (ARD section 16), so its law is restated here.

  Linking mirrors `mix xaas.stop_court`: a receipt is linked to work order
  `O` when `identity.subject` is `O`'s identity (or `identity.work_order`
  names `O`'s IRI) and `identity.tuple_digest` equals `O`'s contract tuple
  digest; to gate `G` of root `R` when `identity.subject` is `"R/G"`.
  """

  alias GgenIgniter.Digest
  alias GgenIgniter.SemanticJira.Bootstrap.Guard

  @sha ~r/\A[0-9a-f]{40}\z/
  @short_sha ~r/\A[0-9a-f]{7,40}\z/
  @digest ~r/\Asha256:[0-9a-f]{64}\z/
  @hex64 ~r/\A[0-9a-f]{64}\z/
  @standing ~r/\A(UNKNOWN|PARTIAL_ALIVE|ALIVE|BLOCKED(:.+)?|BUILD_BROKEN|UNSUPPORTED(\(.+\))?|REFUSED\(.+\))\z/s
  # SOVEREIGN is deliberately NOT a ceiling here: the fleet R schema's
  # `authority.ceiling` enum is the closed set OBSERVE|SELECT|CONSTRUCT|DO and
  # this module validates receipts against that closed set. A work order's
  # `authority_requirement: "SOVEREIGN"` (the 0x04 kind) projects at ceiling
  # DO with the requirement carried separately (`bootstrap.ex`'s kernel
  # "requirement" field); the SOVEREIGN authority law is SovereignLease.admit/3,
  # never a widened ceiling. See the same note in `r_projection.ex`.
  @ceilings ~w(OBSERVE SELECT CONSTRUCT DO)
  @broken_terms ~w(mu_on_O admission_vacuous mu_unlawful R_missing_identity R_missing_authority
    R_missing_consequence R_missing_replay R_missing_standing R_not_fed_back)
  # Precedence when several current receipts are linked to one node.
  @precedence ~w(ALIVE REFUSED BLOCKED UNSUPPORTED BUILD_BROKEN PARTIAL_ALIVE UNKNOWN)

  @type entry :: %{
          ref: String.t(),
          sha256: String.t(),
          receipt: map() | nil,
          errors: [String.t()]
        }

  @typedoc """
  What reading one receipts directory observed, carried into the bootstrap
  state's `inputs` (`status` `"read"` or `"absent"`, `receipts` = files read).
  """
  @type dir_report :: %{String.t() => String.t() | non_neg_integer()}

  @typedoc "A refusal of the whole read: `{code, ref, detail}`."
  @type refusal :: {:forbidden_input | :input_unreadable, String.t(), String.t()}

  @doc """
  Reads every `*.json` file directly inside each `{dir, ref}` (sorted by
  name) and reports each directory. Only a directory that does not exist
  (`enoent`) is tolerated: it contributes no receipt and is reported
  `"absent"`, so the state shows it was not read (a mistyped `--receipts-dir`
  cannot pass as an empty one). Any other listing or file-read error
  (`eacces`, `enotdir`, ...) refuses the whole read `input_unreadable`,
  including a `*.json` entry that is not a readable file (a dangling symlink
  reads `enoent`, a directory `eisdir`): no receipt-named entry is skipped
  silently. A forbidden file path refuses the read `forbidden_input`.
  """
  @spec read([{Path.t(), String.t()}]) :: {:ok, [entry()], [dir_report()]} | {:error, refusal()}
  def read(dirs) do
    Enum.reduce_while(dirs, {:ok, [], []}, fn {dir, ref}, {:ok, entries, reports} ->
      case read_dir(dir, ref) do
        {:ok, read, report} -> {:cont, {:ok, entries ++ read, reports ++ [report]}}
        {:error, _} = refusal -> {:halt, refusal}
      end
    end)
  end

  defp read_dir(dir, ref) do
    case File.ls(dir) do
      {:ok, names} ->
        names
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.sort()
        |> Enum.map(&{Path.join(dir, &1), ref <> "/" <> &1})
        |> Enum.reduce_while({:ok, []}, &read_file/2)
        |> case do
          {:ok, entries} -> {:ok, entries, dir_report(ref, "read", length(entries))}
          refusal -> refusal
        end

      {:error, :enoent} ->
        {:ok, [], dir_report(ref, "absent", 0)}

      {:error, reason} ->
        {:error, {:input_unreadable, ref, "receipts dir: #{:file.format_error(reason)}"}}
    end
  end

  defp dir_report(ref, status, count),
    do: %{"role" => "receipts_dir", "ref" => ref, "status" => status, "receipts" => count}

  defp read_file({path, ref}, {:ok, acc}) do
    with nil <- Guard.forbidden_path(path),
         {:ok, bytes} <- File.read(path) do
      {:cont, {:ok, acc ++ [entry(ref, bytes)]}}
    else
      {:error, reason} ->
        {:halt, {:error, {:input_unreadable, ref, "receipt: #{:file.format_error(reason)}"}}}

      forbidden when is_binary(forbidden) ->
        {:halt, {:error, {:forbidden_input, ref, forbidden}}}
    end
  end

  defp entry(ref, bytes) do
    case Jason.decode(bytes) do
      {:ok, %{} = receipt} ->
        %{ref: ref, sha256: Digest.sha256(bytes), receipt: receipt, errors: check(receipt)}

      {:ok, _other} ->
        %{ref: ref, sha256: Digest.sha256(bytes), receipt: nil, errors: ["<root>: not an object"]}

      {:error, _} ->
        %{ref: ref, sha256: Digest.sha256(bytes), receipt: nil, errors: ["<root>: not JSON"]}
    end
  end

  # Top-level keys the fleet R v2 schema declares (schema `properties`) plus
  # the v1-era `identity.work_order`/`identity.tuple_digest` fields the
  # bootstrap's own linking law consumes (`names_order?/3`,
  # `classify/5`'s tuple binding). Every OTHER top-level key must be a
  # namespaced `provider_ext.<provider>` extension object.
  @known_top_level_keys ~w(
    identity authority consequence replay standing
    work_order_id origin_authority provider provider_execution_id
    subject_before subject_after replay_binding
  )
  @ext_key ~r/\Aprovider_ext\.[a-z0-9][a-z0-9_.-]*\z/

  @doc "Structural R-schema errors of a decoded receipt (`[]` = admitted)."
  @spec check(map()) :: [String.t()]
  def check(receipt) do
    [
      identity_errors(receipt["identity"]),
      authority_errors(receipt["authority"]),
      consequence_errors(receipt["consequence"]),
      replay_errors(receipt["replay"]),
      standing_errors(receipt["standing"]),
      v2_errors(receipt),
      extension_errors(receipt),
      vacuity_errors(receipt)
    ]
    |> List.flatten()
  end

  ## -- fleet R v2 required keys ----------------------------------------------

  # The schema's v2 additions (`required` list): `work_order_id`,
  # `origin_authority{grant,actor}` (+ optional ceiling enum),
  # `provider{name}`, `provider_execution_id`. One typed string per missing
  # key, so a v1-only receipt refuses with reasons, never a crash.
  defp v2_errors(receipt) do
    [
      require_string(receipt, "receipt", "work_order_id"),
      origin_authority_errors(receipt["origin_authority"]),
      provider_errors(receipt["provider"]),
      require_string(receipt, "receipt", "provider_execution_id")
    ]
    |> List.flatten()
  end

  defp origin_authority_errors(%{} = origin_authority) do
    [
      require_string(origin_authority, "origin_authority", "grant"),
      require_string(origin_authority, "origin_authority", "actor"),
      if(is_nil(origin_authority["ceiling"]) or origin_authority["ceiling"] in @ceilings,
        do: [],
        else: ["origin_authority/ceiling: not in #{inspect(@ceilings)}"]
      )
    ]
  end

  defp origin_authority_errors(_), do: ["origin_authority: required object"]

  defp provider_errors(%{} = provider) do
    [require_string(provider, "provider", "name")]
  end

  defp provider_errors(_), do: ["provider: required object"]

  ## -- extension-namespace rule -----------------------------------------------

  # The schema's top level stays OPEN, but the fleet validator (whose rule
  # this restates) refuses un-namespaced extension keys: every top-level key
  # outside `@known_top_level_keys` must match
  # `^provider_ext\.[a-z0-9][a-z0-9_.-]*$` and carry an object.
  defp extension_errors(receipt) when is_map(receipt) do
    for {key, value} <- receipt,
        key not in @known_top_level_keys,
        not Regex.match?(@ext_key, key) or not is_map(value),
        do: ext_error(key, value)
  end

  defp extension_errors(_), do: []

  defp ext_error(key, value) when is_map(value),
    do: [
      "#{inspect(key)}: extension keys must be namespaced " <>
        "(#{Regex.source(@ext_key)}), not bare at top level"
    ]

  defp ext_error(key, _value),
    do: ["#{inspect(key)}: namespaced extension object required (#{Regex.source(@ext_key)})"]

  defp identity_errors(%{} = identity) do
    [
      require_string(identity, "identity", "subject"),
      require_string(identity, "identity", "repo"),
      require_match(identity, "identity", "subject_sha", @sha),
      require_match(identity, "identity", "base_sha", @sha),
      optional_match(identity, "identity", "graph_hash", @digest)
    ]
  end

  defp identity_errors(_), do: ["identity: required object"]

  defp authority_errors(%{} = authority) do
    [
      if(authority["ceiling"] in @ceilings,
        do: [],
        else: ["authority/ceiling: not in #{inspect(@ceilings)}"]
      ),
      require_string(authority, "authority", "grant"),
      require_string(authority, "authority", "actor")
    ]
  end

  defp authority_errors(_), do: ["authority: required object"]

  defp consequence_errors(%{} = consequence) do
    [
      list_of(
        consequence,
        "consequence",
        "commits",
        &(is_binary(&1) and Regex.match?(@short_sha, &1))
      ),
      list_of(consequence, "consequence", "files_changed", &is_binary/1),
      list_of(consequence, "consequence", "remote_effects", &is_binary/1)
    ]
  end

  defp consequence_errors(_), do: ["consequence: required object"]

  defp replay_errors(%{"commands" => [_ | _] = commands}) do
    commands
    |> Enum.with_index()
    |> Enum.flat_map(fn {command, index} -> command_errors(command, index) end)
  end

  defp replay_errors(_), do: ["replay/commands: required non-empty array"]

  defp command_errors(%{} = command, index) do
    where = "replay/commands/#{index}"

    [
      require_string(command, where, "cmd"),
      require_string(command, where, "cwd"),
      if(is_integer(command["exit"]), do: [], else: ["#{where}/exit: required integer"]),
      optional_match(command, where, "output_sha256", @hex64)
    ]
    |> List.flatten()
  end

  defp command_errors(_other, index), do: ["replay/commands/#{index}: not an object"]

  defp standing_errors(%{} = standing) do
    value = standing["value"]

    [
      if(is_binary(value) and Regex.match?(@standing, value),
        do: [],
        else: ["standing/value: #{inspect(value)} is not a standing"]
      ),
      require_string(standing, "standing", "derived_from"),
      broken_term_errors(value, standing["broken_term"])
    ]
  end

  defp standing_errors(_), do: ["standing: required object"]

  defp broken_term_errors(value, term) do
    needs? =
      is_binary(value) and String.starts_with?(value, ["BLOCKED", "BUILD_BROKEN", "REFUSED"])

    cond do
      is_nil(term) and needs? -> ["standing/broken_term: required for #{value}"]
      is_nil(term) or term in @broken_terms -> []
      true -> ["standing/broken_term: #{inspect(term)} is not a broken term"]
    end
  end

  defp vacuity_errors(%{
         "standing" => %{"value" => "ALIVE"},
         "replay" => %{"commands" => commands}
       })
       when is_list(commands) do
    if Enum.any?(commands, &(is_map(&1) and &1["exit"] != 0)),
      do: ["standing: ALIVE with a non-zero replay exit (admission_vacuous)"],
      else: []
  end

  defp vacuity_errors(_), do: []

  defp require_string(map, where, key) do
    case map[key] do
      value when is_binary(value) and value != "" -> []
      _ -> ["#{where}/#{key}: required non-empty string"]
    end
  end

  defp require_match(map, where, key, regex) do
    if is_binary(map[key]) and Regex.match?(regex, map[key]),
      do: [],
      else: ["#{where}/#{key}: does not match #{Regex.source(regex)}"]
  end

  defp optional_match(map, where, key, regex) do
    if is_map_key(map, key), do: require_match(map, where, key, regex), else: []
  end

  defp list_of(map, where, key, valid?) do
    case map[key] do
      list when is_list(list) ->
        if Enum.all?(list, valid?), do: [], else: ["#{where}/#{key}: invalid item"]

      _ ->
        ["#{where}/#{key}: required array"]
    end
  end

  @doc "True when `entry` names work order `id` / IRI local name `local`."
  @spec names_order?(entry(), String.t(), String.t() | nil) :: boolean()
  def names_order?(%{receipt: %{"identity" => %{} = identity}}, id, local) do
    identity["subject"] == id or
      (is_binary(local) and is_binary(identity["work_order"]) and
         GgenIgniter.SemanticJira.Prose.names?(identity["work_order"], local))
  end

  def names_order?(_entry, _id, _local), do: false

  @doc "True when `entry`'s `identity.subject` is exactly `subject`."
  @spec names_subject?(entry(), String.t()) :: boolean()
  def names_subject?(%{receipt: %{"identity" => %{"subject" => subject}}}, subject), do: true
  def names_subject?(_entry, _subject), do: false

  @doc "The receipt's standing value (or `nil`)."
  @spec standing(entry()) :: String.t() | nil
  def standing(%{receipt: %{"standing" => %{"value" => value}}}) when is_binary(value), do: value
  def standing(_entry), do: nil

  @doc "The receipt's `identity.<key>`."
  @spec identity(entry(), String.t()) :: term()
  def identity(%{receipt: %{"identity" => %{} = identity}}, key), do: identity[key]
  def identity(_entry, _key), do: nil

  @doc """
  The best of several linked, current receipts (standing precedence
  #{Enum.join(@precedence, " > ")}, then ref).
  """
  @spec best([map()]) :: map() | nil
  def best([]), do: nil

  def best(candidates) do
    Enum.min_by(candidates, fn candidate ->
      {Enum.find_index(@precedence, &String.starts_with?(candidate.standing, &1)) || 99,
       candidate.ref}
    end)
  end

  @doc "Kernel standing of a receipt standing (`BLOCKED:x` -> `BLOCKED`, `UNSUPPORTED(x)` -> `UNSUPPORTED`)."
  @spec kernel_standing(String.t()) :: String.t()
  def kernel_standing("BLOCKED" <> _), do: "BLOCKED"
  def kernel_standing("UNSUPPORTED" <> _), do: "UNSUPPORTED"
  def kernel_standing(value), do: value
end
