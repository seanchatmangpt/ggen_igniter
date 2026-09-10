defmodule GgenIgniter.FrontierReleasePlan do
  @moduledoc """
  Builds a content-addressed Frontier Release response plan as a
  `GgenIgniter.RuntimeShape` projection without executing any step.

  This module deliberately composes the existing RuntimeShape IR instead of
  introducing a second project-spec language:

    * `new/2` validates an already-admitted source `RuntimeShape`, validates a
      bounded response-plan vocabulary, and returns a new RuntimeShape whose
      `projections` contain structured executable/argv intents rather than
      shell strings.
    * `steps/1` returns the ordered projection steps for inspection or later
      routing by an authority-aware runtime.
    * `do_intents/1` returns only consequential DO intents. In v1 the only DO
      intent this module can describe is `gh repo create`, and that intent is
      always marked broker-required and receipt-required.
    * `construct_intents/1` returns reversible local scaffold/manufacture
      intents that remain CONSTRUCT and never inherit GitHub authority.

  The source RuntimeShape remains the admitted semantic input. The returned
  RuntimeShape is another portable, content-addressed projection and grants no
  authority by itself. `GgenIgniter.FrontierReleasePlan` never invokes
  `System.cmd/3`, `GgenIgniter.Actuate`, `Mix.Tasks.GgenIgniter.Sync`, `gh`, or
  Igniter. Execution belongs to the existing admission/actuation/receipt
  machinery. In particular, a later broker may translate the structured
  `gh repo create` intent into DO only after exact-scope authorization.

  Project scaffolding is represented with the repository's already-observed
  `mix igniter.new` convention, while ontology manufacture is represented with
  the implemented `mix ggen_igniter.sync --pack-dir ...` CLI surface. Reusing
  an admitted repository does not scaffold a replacement project; only
  `repository_mode: "create"` adds the scaffold and repository-create intents.
  This module does not claim that any tool ran merely because its intent is
  present in a RuntimeShape.
  """

  alias GgenIgniter.RuntimeShape

  @response_modes ~w(reuse compose extend invent)
  @repository_modes ~w(reuse create)
  @visibilities ~w(public private)

  @required ~w(
    opportunity_id
    project_name
    project_dir
    target_repository
    pack_dir
    response_mode
    repository_mode
    visibility
  )

  @type attrs :: map() | keyword()

  @doc "Builds a non-actuating, content-addressed Frontier Release response-plan RuntimeShape."
  @spec new(RuntimeShape.t(), attrs()) :: {:ok, RuntimeShape.t()} | {:error, [term()]}
  def new(%RuntimeShape{} = source_shape, attrs) when is_map(attrs) or is_list(attrs) do
    with :ok <- RuntimeShape.validate(source_shape),
         {:ok, normalized} <- normalize_attrs(attrs),
         :ok <- validate_attrs(normalized),
         projection <- projection(normalized),
         {:ok, plan_shape} <- build_plan_shape(source_shape, normalized, projection) do
      {:ok, plan_shape}
    else
      {:error, errors} when is_list(errors) -> {:error, errors}
      {:error, error} -> {:error, [error]}
    end
  end

  def new(_source_shape, _attrs),
    do: {:error, [{:invalid_source_shape, :expected_runtime_shape}]}

  @doc "Returns the ordered structured steps from the most recently appended Frontier Release plan projection."
  @spec steps(RuntimeShape.t()) :: {:ok, [map()]} | {:error, term()}
  def steps(%RuntimeShape{projections: projections}) do
    case projections |> Enum.reverse() |> Enum.find(&frontier_projection?/1) do
      %{"steps" => steps} when is_list(steps) -> {:ok, steps}
      _ -> {:error, :frontier_release_projection_not_found}
    end
  end

  @doc "Returns only brokered consequential DO intents from a Frontier Release plan."
  @spec do_intents(RuntimeShape.t()) :: {:ok, [map()]} | {:error, term()}
  def do_intents(%RuntimeShape{} = shape) do
    with {:ok, steps} <- steps(shape) do
      {:ok, Enum.filter(steps, &(&1["class"] == "DO"))}
    end
  end

  @doc "Returns reversible CONSTRUCT intents from a Frontier Release plan."
  @spec construct_intents(RuntimeShape.t()) :: {:ok, [map()]} | {:error, term()}
  def construct_intents(%RuntimeShape{} = shape) do
    with {:ok, steps} <- steps(shape) do
      {:ok, Enum.filter(steps, &(&1["class"] == "CONSTRUCT"))}
    end
  end

  defp normalize_attrs(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs) do
      normalize_attrs(Map.new(attrs))
    else
      {:error, :invalid_attributes}
    end
  end

  defp normalize_attrs(attrs) when is_map(attrs) do
    normalized =
      Map.new(attrs, fn {key, value} ->
        normalized_key = if is_atom(key), do: Atom.to_string(key), else: key
        {normalized_key, value}
      end)

    unknown = Map.keys(normalized) -- @required

    if unknown == [] do
      {:ok, normalized}
    else
      {:error, {:unknown_fields, Enum.sort(unknown)}}
    end
  end

  defp validate_attrs(attrs) do
    errors =
      []
      |> validate_required_strings(attrs)
      |> validate_member(attrs, "response_mode", @response_modes)
      |> validate_member(attrs, "repository_mode", @repository_modes)
      |> validate_member(attrs, "visibility", @visibilities)
      |> validate_create_project_identity(attrs)

    case Enum.reverse(errors) do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp validate_required_strings(errors, attrs) do
    Enum.reduce(@required, errors, fn key, acc ->
      case Map.get(attrs, key) do
        value when is_binary(value) and byte_size(value) > 0 -> acc
        value -> [{:invalid_field, key, value} | acc]
      end
    end)
  end

  defp validate_member(errors, attrs, key, allowed) do
    value = Map.get(attrs, key)
    if value in allowed, do: errors, else: [{:invalid_enum, key, value, allowed} | errors]
  end

  defp validate_create_project_identity(
         errors,
         %{"repository_mode" => "create", "project_name" => name, "project_dir" => dir}
       )
       when is_binary(name) and is_binary(dir) do
    if Path.basename(dir) == name do
      errors
    else
      [{:project_name_directory_mismatch, name, dir} | errors]
    end
  end

  defp validate_create_project_identity(errors, _attrs), do: errors

  defp projection(attrs) do
    %{
      "kind" => "frontier_release_response_plan",
      "opportunity_id" => attrs["opportunity_id"],
      "response_mode" => attrs["response_mode"],
      "repository_mode" => attrs["repository_mode"],
      "target_repository" => attrs["target_repository"],
      "project_name" => attrs["project_name"],
      "project_dir" => attrs["project_dir"],
      "pack_dir" => attrs["pack_dir"],
      "authority_ceiling" => "CONSTRUCT",
      "steps" => build_steps(attrs)
    }
  end

  defp build_steps(%{"repository_mode" => "reuse"} = attrs) do
    [manufacture_intent(attrs), verify_intent(attrs)]
  end

  defp build_steps(%{"repository_mode" => "create"} = attrs) do
    [
      scaffold_intent(attrs),
      manufacture_intent(attrs),
      verify_intent(attrs),
      repository_create_intent(attrs)
    ]
  end

  defp scaffold_intent(attrs) do
    %{
      "id" => "scaffold-local-project",
      "class" => "CONSTRUCT",
      "reversible" => true,
      "broker_required" => false,
      "receipt_required" => true,
      "executable" => "mix",
      "argv" => ["igniter.new", attrs["project_name"]],
      "cwd" => Path.dirname(attrs["project_dir"])
    }
  end

  defp manufacture_intent(attrs) do
    %{
      "id" => "manufacture-from-pack",
      "class" => "CONSTRUCT",
      "reversible" => true,
      "broker_required" => false,
      "receipt_required" => true,
      "executable" => "mix",
      "argv" => [
        "ggen_igniter.sync",
        "--pack-dir",
        attrs["pack_dir"],
        "--manifest-dir",
        attrs["project_dir"],
        "--verify-cwd",
        attrs["project_dir"]
      ],
      "cwd" => attrs["project_dir"]
    }
  end

  defp verify_intent(attrs) do
    %{
      "id" => "verify-local-project",
      "class" => "OBSERVE",
      "reversible" => true,
      "broker_required" => false,
      "receipt_required" => true,
      "executable" => "mix",
      "argv" => ["compile", "--warnings-as-errors"],
      "cwd" => attrs["project_dir"]
    }
  end

  defp repository_create_intent(attrs) do
    %{
      "id" => "create-github-repository",
      "class" => "DO",
      "reversible" => false,
      "broker_required" => true,
      "receipt_required" => true,
      "required_authority" => "create_repository",
      "executable" => "gh",
      "argv" => [
        "repo",
        "create",
        attrs["target_repository"],
        "--#{attrs["visibility"]}",
        "--source",
        ".",
        "--remote",
        "origin"
      ],
      "cwd" => attrs["project_dir"]
    }
  end

  defp build_plan_shape(source_shape, attrs, projection) do
    RuntimeShape.new(%{
      subject_id: "#{source_shape.subject_id}#frontier-release/#{attrs["opportunity_id"]}",
      source_digest: source_shape.source_digest,
      graph_digest: source_shape.graph_digest,
      ontology_versions: source_shape.ontology_versions,
      projections: source_shape.projections ++ [projection],
      admission: %{
        "source_shape_digest" => source_shape.shape_digest,
        "authority_ceiling" => "CONSTRUCT",
        "do_intents_require_external_broker" => true
      },
      provenance: %{
        "source_subject_id" => source_shape.subject_id,
        "source_shape_digest" => source_shape.shape_digest
      }
    })
  end

  defp frontier_projection?(%{"kind" => "frontier_release_response_plan"}), do: true
  defp frontier_projection?(_projection), do: false
end
