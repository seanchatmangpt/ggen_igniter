defmodule GgenIgniter.GallTicket do
  @moduledoc """
  GALL Semantic Work Fabric ticket projection (v26.9.18 PRD §43.4): resolves one
  `gall:` checkpoint by IRI inside a checkpoint TTL document and renders it into
  a Markdown work ticket via the `gall_work` pack's
  `priv/ggen/gall_work/templates/ticket.md.eex`, reusing the corpus's standard
  pipeline -- `GgenIgniter.Ontology.load!/1` -> `GgenIgniter.Query.run/2` ->
  `GgenIgniter.Render.render/2` -- rather than reimplementing any of it.

  ## Provenance (PRD §42) -- every rendered ticket is a projection

  Every rendered ticket embeds a provenance footer carrying the **source graph
  digest** (`GgenIgniter.Digest.sha256/1` over the exact byte content of the
  input TTL document -- the canonical input; same bytes, same digest) plus the
  **pack identity** (`gall_work` + its namespace IRI), and the template itself
  carries the "generated file -- edit the ontology, not this file" marker, so a
  reader of any rendered ticket can tell it is manufactured, re-derive the
  source it came from, and know that hand-edits to the artifact are contract
  violations.

  ## Determinism (PRD §53)

  `render_ticket/3` is a pure function of (source bytes, checkpoint IRI,
  template bytes): no clock, no randomness, no ambient state. The `sparql`
  engine's row order is not contractual (`GgenIgniter.Query`'s moduledoc), so
  every multi-valued slot is sorted lexicographically in Elixir before
  rendering, and every single-valued slot refuses ambiguity instead of picking
  a row. Therefore `render_ticket/3` on the same input twice is byte-identical:
  `Render(TTL)_1 = Render(TTL)_2`.

  ## Typed refusals (never raises for refused input)

  Parse failure raises (existing `Ontology.load!/1` contract), but every
  semantic problem with the CHECKPOINT is a `{:refused, reason}` tuple:

    * `{:source_unreadable, path, reason}` -- the TTL document cannot be read.
    * `{:invalid_iri, iri}` -- the checkpoint IRI cannot be safely embedded in
      a SPARQL query.
    * `{:unknown_checkpoint, iri}` -- the IRI appears nowhere in the graph.
    * `{:not_a_checkpoint, iri, types}` -- the IRI exists but carries no
      `gall:Checkpoint`/`gall:CodingCheckpoint` type.
    * `{:missing_standing, iri}` -- no `gall:hasStanding`; standing is the
      checkpoint's primary evidence state and is never defaulted.
    * `{:ambiguous_standing, iri, standings}` -- more than one standing.
    * `{:ambiguous_slot, slot, iri, values}` -- a declared-single-valued slot
      (`repository`, `base_sha`, `goal`) has multiple values; silent pruning of
      alternatives is forbidden, so this is a refusal, not a pick.
    * `{:template_unreadable, path, reason}` -- the pack template is missing.

  ## Value formatting split

  The template owns SECTION STRUCTURE; this module owns VALUE FORMATTING
  (refusals, nil-handling, backticks, list lines). Bindings are always
  non-nil, fully formatted strings / lists of lines, which keeps the EEx
  trivially deterministic.
  """

  alias GgenIgniter.{Digest, Ontology, Query, Render}

  @gall "https://semantic-a2a.dev/gall#"
  @pack_name "gall_work"
  @pack_namespace @gall
  @checkpoint_class @gall <> "Checkpoint"
  @coding_checkpoint_class @gall <> "CodingCheckpoint"
  @rdfs_label "http://www.w3.org/2000/01/rdf-schema#label"

  @doc "Absolute default template path, resolved at call time via `Application.app_dir/2`."
  @spec default_template_path() :: String.t()
  def default_template_path do
    Application.app_dir(:ggen_igniter, "priv/ggen/#{@pack_name}/templates/ticket.md.eex")
  end

  @doc """
  Renders the checkpoint `checkpoint_iri` from the TTL document at
  `source_path` into Markdown ticket text.

  Returns `{:ok, markdown}` or `{:refused, reason}` -- see the module docs for
  the full refusal taxonomy. Accepts `:template` to override the pack
  template path (tests and variants); defaults to the `gall_work` pack's
  `ticket.md.eex`.
  """
  @spec render_ticket(String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:refused, term()}
  def render_ticket(source_path, checkpoint_iri, opts \\ [])
      when is_binary(source_path) and is_binary(checkpoint_iri) and is_list(opts) do
    with {:ok, ttl_bytes} <- read_source(source_path),
         :ok <- validate_iri(checkpoint_iri),
         graph <- Ontology.load!(source_path),
         {:ok, checkpoint} <- resolve_checkpoint(graph, checkpoint_iri),
         {:ok, bindings} <- build_bindings(graph, checkpoint, ttl_bytes, source_path),
         {:ok, template} <- read_template(Keyword.get(opts, :template, default_template_path())) do
      {:ok, Render.render(template, bindings)}
    end
  end

  # ── Resolution + validation ────────────────────────────────────────────────

  defp read_source(path) do
    case File.read(path) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, reason} -> {:refused, {:source_unreadable, path, reason}}
    end
  end

  defp read_template(path) do
    case File.read(path) do
      {:ok, template} -> {:ok, template}
      {:error, reason} -> {:refused, {:template_unreadable, path, reason}}
    end
  end

  # The IRI is interpolated inside <> in SPARQL; a '>' in it would terminate
  # the IRI early and silently change the query's meaning, so angle brackets
  # and whitespace are refused at the boundary instead.
  defp validate_iri(iri) do
    if String.contains?(iri, [">", "<", " ", "\n", "\t"]) do
      {:refused, {:invalid_iri, iri}}
    else
      :ok
    end
  end

  defp resolve_checkpoint(graph, iri) do
    exists? = graph |> subject_rows(iri, "?p ?o") |> Enum.any?()
    types = graph |> subject_rows(iri, "a ?v") |> values() |> Enum.sort()

    cond do
      not exists? ->
        {:refused, {:unknown_checkpoint, iri}}

      @checkpoint_class not in types and @coding_checkpoint_class not in types ->
        {:refused, {:not_a_checkpoint, iri, types}}

      true ->
        {:ok,
         %{
           iri: iri,
           type_label:
             if(@coding_checkpoint_class in types, do: "CodingCheckpoint", else: "Checkpoint")
         }}
    end
  end

  # ── Bindings assembly ──────────────────────────────────────────────────────

  defp build_bindings(graph, checkpoint, ttl_bytes, source_path) do
    iri = checkpoint.iri

    with {:ok, standing_iri} <- require_standing(graph, iri),
         {:ok, repository} <- single(graph, iri, "targetsRepository", :repository),
         {:ok, base_sha} <- single(graph, iri, "baseSha", :base_sha),
         {:ok, goal} <- single(graph, iri, "goal", :goal) do
      {:ok,
       %{
         iri: iri,
         label: label_or_local(graph, iri),
         checkpoint_type: checkpoint.type_label,
         standing: local_name(standing_iri),
         source_document: source_path,
         repository_text: format_or(repository, &"<" <> &1 <> ">"),
         base_sha_text: format_or(base_sha, &"`" <> &1 <> "`"),
         goal_text: goal || "(not declared)",
         dependencies:
           multi(graph, iri, "dependsOn", fn dep ->
             "`" <> dep <> "`" <> label_suffix(graph, dep)
           end),
         allowed_paths: multi(graph, iri, "allowedPath", &"`" <> &1 <> "`"),
         requires_capabilities:
           multi(graph, iri, "requiresCapability", &label_or_local(graph, &1)),
         forbids_capabilities:
           multi(graph, iri, "forbidsCapability", &label_or_local(graph, &1)),
         acceptance_criteria: hop(graph, iri, "hasAcceptance", "criterion"),
         falsifiers: hop(graph, iri, "hasFalsifier", "statement"),
         verifiers: verifiers(graph, iri),
         source_digest: Digest.sha256(ttl_bytes),
         pack_name: @pack_name,
         pack_namespace: @pack_namespace
       }}
    end
  end

  defp require_standing(graph, iri) do
    case graph |> subject_rows(iri, "<#{@gall}hasStanding> ?v") |> values() |> Enum.sort() do
      [] -> {:refused, {:missing_standing, iri}}
      [one] -> {:ok, one}
      many -> {:refused, {:ambiguous_standing, iri, many}}
    end
  end

  # A declared-single-valued slot: absent is renderable ("(not declared)"),
  # ambiguous is a refusal -- picking a row would be silent pruning.
  defp single(graph, iri, property, slot) do
    case graph |> subject_rows(iri, "<#{@gall}#{property}> ?v") |> values() |> Enum.sort() do
      [] -> {:ok, nil}
      [one] -> {:ok, one}
      many -> {:refused, {:ambiguous_slot, slot, iri, many}}
    end
  end

  # ── Multi-valued slot rendering (sorted => deterministic) ──────────────────

  defp multi(graph, iri, property, format) do
    graph
    |> subject_rows(iri, "<#{@gall}#{property}> ?v")
    |> values()
    |> Enum.map(fn value -> "- " <> format.(to_string(value)) end)
    |> Enum.sort()
    |> or_none()
  end

  defp hop(graph, iri, property, value_property) do
    graph
    |> subject_rows(iri, "<#{@gall}#{property}> ?a . ?a <#{@gall}#{value_property}> ?v")
    |> values()
    |> Enum.map(&"- " <> to_string(&1))
    |> Enum.sort()
    |> or_none()
  end

  defp verifiers(graph, iri) do
    graph
    |> subject_rows(iri, "<#{@gall}requiresVerifier> ?v")
    |> values()
    |> Enum.sort()
    |> Enum.map(fn verifier_iri ->
      commands = graph |> subject_rows(verifier_iri, "<#{@gall}command> ?v") |> values()

      base = "- " <> label_or_local(graph, verifier_iri)

      case commands do
        [] ->
          base

        many ->
          command = many |> Enum.map(&to_string/1) |> Enum.sort() |> hd()
          base <> " — `" <> command <> "`"
      end
    end)
    |> or_none()
  end

  defp format_or(nil, _format), do: "(not declared)"
  defp format_or(value, format), do: format.(to_string(value))

  defp or_none([]), do: ["(none)"]
  defp or_none(lines), do: lines

  # `label-or-local-name`: the graph's rdfs:label when present (minimum taken
  # so multiple labels stay deterministic), else the IRI's local name. Applied
  # uniformly to capabilities, verifiers, dependencies, and the checkpoint
  # itself, so both declared and undeclared-but-referenced individuals render
  # sensibly.
  defp label_or_local(graph, iri) do
    pick_label(graph, iri) || local_name(iri)
  end

  defp label_suffix(graph, iri) do
    case pick_label(graph, iri) do
      nil -> ""
      label -> " — " <> label
    end
  end

  defp pick_label(graph, iri) do
    case graph |> subject_rows(iri, "<#{@rdfs_label}> ?v") |> values() do
      [] -> nil
      labels -> labels |> Enum.map(&to_string/1) |> Enum.sort() |> hd()
    end
  end

  defp local_name(iri) when is_binary(iri) do
    iri |> String.split(["#", "/"]) |> List.last()
  end

  # ── SPARQL plumbing (all through the corpus's GgenIgniter.Query) ──────────

  defp subject_rows(graph, subject_iri, body) do
    Query.run(graph, "SELECT ?v WHERE { <" <> subject_iri <> "> " <> body <> " }")
  end

  defp values(rows), do: Enum.map(rows, &Map.fetch!(&1, "v"))
end
