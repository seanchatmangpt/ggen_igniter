defmodule GgenIgniter.RuntimeShape do
  @moduledoc """
  Defines the pure-data, content-addressed intermediate representation that
  separates an admitted semantic shape from any particular Ash, Spark,
  Reactor, Phoenix, AsyncAPI, or source-code projection.

  This module deliberately owns only CONSTRUCT-time semantic identity:

    * `new/1` and `new!/1` admit a closed set of top-level RuntimeShape fields
      and refuse unknown fields instead of silently carrying unmodeled state.
    * `validate/1` verifies required identity fields and recursively refuses
      executable/runtime-only Elixir values such as functions, PIDs, ports,
      references, tuples, structs, and non-string nested map keys. A
      RuntimeShape is portable data, not ambient executable code.
    * `semantic_map/1` returns the exact shape content covered by the semantic
      digest, excluding `shape_digest` itself to avoid circular identity.
    * `digest/1` computes an order-independent `sha256:` identity over the
      complete nested semantic map while preserving list order, so equivalent
      map insertion orders share one identity and semantically different lists
      do not.
    * `to_map/1` and `from_map/1` provide a string-keyed, JSON-compatible
      interchange surface without ever converting arbitrary external strings
      into atoms.

  The canonical ontology/graph remains upstream of this module. A
  `%RuntimeShape{}` is a bounded projection of already-admitted semantics, not
  a replacement canonical source. Likewise, this module never actuates: any
  future Ash/Reactor projection that causes an external consequence remains
  subject to this repository's existing admission/receipt boundary.

  Ash remains intentionally consumer-side and optional in this repository
  (ADR-0002). Keeping this IR free of Ash/Spark/Reactor structs is what lets the
  same admitted shape feed several projectors without introducing a second
  semantic source of truth.
  """

  @schema_version 1

  @fields [
    :schema_version,
    :subject_id,
    :source_digest,
    :graph_digest,
    :shape_digest,
    :ontology_versions,
    :attributes,
    :relationships,
    :actions,
    :policies,
    :public_facets,
    :native_facets,
    :bindings,
    :projections,
    :temporal,
    :measurements,
    :admission,
    :provenance,
    :resource_budget
  ]

  @string_fields Map.new(@fields, fn field -> {Atom.to_string(field), field} end)
  @required_fields [:subject_id, :source_digest, :graph_digest, :admission]

  @list_fields [
    :attributes,
    :relationships,
    :actions,
    :policies,
    :public_facets,
    :bindings,
    :projections,
    :measurements
  ]

  @map_fields [:ontology_versions, :native_facets, :admission, :provenance, :resource_budget]
  @map_or_nil_fields [:temporal]

  @typedoc "A stable content digest using the same `sha256:` vocabulary as `GgenIgniter.Receipt`."
  @type digest :: String.t()

  @typedoc "Portable admitted semantic shape. No executable/runtime-only values are permitted."
  @type t :: %__MODULE__{
          schema_version: pos_integer(),
          subject_id: String.t(),
          source_digest: digest(),
          graph_digest: digest(),
          shape_digest: digest() | nil,
          ontology_versions: map(),
          attributes: [map()],
          relationships: [map()],
          actions: [map()],
          policies: [map()],
          public_facets: [map()],
          native_facets: map(),
          bindings: [map()],
          projections: [map()],
          temporal: map() | nil,
          measurements: [map()],
          admission: map(),
          provenance: map(),
          resource_budget: map()
        }

  @enforce_keys @required_fields
  defstruct schema_version: @schema_version,
            subject_id: nil,
            source_digest: nil,
            graph_digest: nil,
            shape_digest: nil,
            ontology_versions: %{},
            attributes: [],
            relationships: [],
            actions: [],
            policies: [],
            public_facets: [],
            native_facets: %{},
            bindings: [],
            projections: [],
            temporal: nil,
            measurements: [],
            admission: %{},
            provenance: %{},
            resource_budget: %{}

  @doc "Builds and validates a RuntimeShape, computing `shape_digest` from its semantic content."
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, [term()]}
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    with {:ok, normalized} <- normalize_attrs(attrs),
         shape <- struct(__MODULE__, normalized),
         :ok <- validate(shape) do
      {:ok, %{shape | shape_digest: digest(shape)}}
    end
  end

  @doc "Like `new/1`, but raises `ArgumentError` when the shape is not admitted."
  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, shape} -> shape
      {:error, errors} -> raise ArgumentError, "invalid runtime shape: #{inspect(errors)}"
    end
  end

  @doc "Validates required fields, field containers, and recursive portable-data constraints."
  @spec validate(t()) :: :ok | {:error, [term()]}
  def validate(%__MODULE__{} = shape) do
    errors =
      []
      |> validate_schema_version(shape)
      |> validate_required_binaries(shape)
      |> validate_list_fields(shape)
      |> validate_map_fields(shape)
      |> validate_map_or_nil_fields(shape)
      |> validate_portable(shape)

    case Enum.reverse(errors) do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  @doc "Returns the exact string-keyed semantic content covered by `digest/1`."
  @spec semantic_map(t()) :: map()
  def semantic_map(%__MODULE__{} = shape) do
    shape
    |> Map.from_struct()
    |> Map.delete(:shape_digest)
    |> stringify_top_level_keys()
  end

  @doc "Computes the deterministic `sha256:` digest for a RuntimeShape's semantic content."
  @spec digest(t()) :: digest()
  def digest(%__MODULE__{} = shape) do
    canonical = canonical_value(semantic_map(shape))
    encoded = Jason.encode!(canonical)
    GgenIgniter.Digest.sha256(encoded)
  end

  @doc "Converts a RuntimeShape to a JSON-compatible, string-keyed map including its digest."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = shape) do
    shape
    |> Map.from_struct()
    |> stringify_top_level_keys()
  end

  @doc "Builds a RuntimeShape from its string-keyed or atom-keyed top-level interchange map."
  @spec from_map(map()) :: {:ok, t()} | {:error, [term()]}
  def from_map(map) when is_map(map), do: new(map)

  @doc "The closed set of top-level RuntimeShape fields accepted by `new/1`."
  @spec fields() :: [atom()]
  def fields, do: @fields

  @doc "Current RuntimeShape schema version."
  @spec schema_version() :: pos_integer()
  def schema_version, do: @schema_version

  defp normalize_attrs(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs) do
      normalize_attrs(Map.new(attrs))
    else
      {:error, [{:invalid_attributes, :expected_map_or_keyword}]}
    end
  end

  defp normalize_attrs(attrs) when is_map(attrs) do
    Enum.reduce_while(attrs, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case normalize_key(key) do
        {:ok, normalized_key} -> {:cont, {:ok, Map.put(acc, normalized_key, value)}}
        :error -> {:halt, {:error, [{:unknown_field, key}]}}
      end
    end)
  end

  defp normalize_key(key) when key in @fields, do: {:ok, key}

  defp normalize_key(key) when is_binary(key) do
    case Map.fetch(@string_fields, key) do
      {:ok, field} -> {:ok, field}
      :error -> :error
    end
  end

  defp normalize_key(_key), do: :error

  defp validate_schema_version(errors, %__MODULE__{schema_version: version})
       when is_integer(version) and version > 0,
       do: errors

  defp validate_schema_version(errors, %__MODULE__{schema_version: version}),
    do: [{:invalid_field, :schema_version, version} | errors]

  defp validate_required_binaries(errors, shape) do
    Enum.reduce([:subject_id, :source_digest, :graph_digest], errors, fn field, acc ->
      case Map.fetch!(shape, field) do
        value when is_binary(value) and byte_size(value) > 0 -> acc
        value -> [{:invalid_field, field, value} | acc]
      end
    end)
  end

  defp validate_list_fields(errors, shape) do
    Enum.reduce(@list_fields, errors, fn field, acc ->
      case Map.fetch!(shape, field) do
        value when is_list(value) -> acc
        value -> [{:invalid_field, field, value} | acc]
      end
    end)
  end

  defp validate_map_fields(errors, shape) do
    Enum.reduce(@map_fields, errors, fn field, acc ->
      case Map.fetch!(shape, field) do
        value when is_map(value) and not is_struct(value) -> acc
        value -> [{:invalid_field, field, value} | acc]
      end
    end)
  end

  defp validate_map_or_nil_fields(errors, shape) do
    Enum.reduce(@map_or_nil_fields, errors, fn field, acc ->
      case Map.fetch!(shape, field) do
        nil -> acc
        value when is_map(value) and not is_struct(value) -> acc
        value -> [{:invalid_field, field, value} | acc]
      end
    end)
  end

  defp validate_portable(errors, shape) do
    semantic_map(shape)
    |> portable_errors([])
    |> Enum.reduce(errors, fn error, acc -> [error | acc] end)
  end

  defp portable_errors(value, _path)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value),
       do: []

  defp portable_errors(value, path) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.flat_map(fn {item, index} -> portable_errors(item, [index | path]) end)
  end

  defp portable_errors(value, path) when is_map(value) and not is_struct(value) do
    Enum.flat_map(value, fn {key, item} ->
      key_errors =
        if is_binary(key) do
          []
        else
          [{:nonportable_key, Enum.reverse(path), key}]
        end

      key_errors ++ portable_errors(item, [key | path])
    end)
  end

  defp portable_errors(value, path),
    do: [{:nonportable_value, Enum.reverse(path), portable_type(value)}]

  defp portable_type(value) when is_function(value), do: :function
  defp portable_type(value) when is_pid(value), do: :pid
  defp portable_type(value) when is_port(value), do: :port
  defp portable_type(value) when is_reference(value), do: :reference
  defp portable_type(value) when is_tuple(value), do: :tuple
  defp portable_type(value) when is_struct(value), do: {:struct, value.__struct__}
  defp portable_type(_value), do: :unsupported

  defp stringify_top_level_keys(map) do
    Map.new(map, fn {key, value} -> {Atom.to_string(key), value} end)
  end

  # JSON objects are unordered, while Jason is free to traverse an Elixir map
  # in any VM-dependent map order. Converting every map recursively into a
  # sorted list of [key, value] pairs makes the encoded identity deterministic
  # without creating atoms or changing list semantics.
  defp canonical_value(value) when is_map(value) and not is_struct(value) do
    value
    |> Enum.map(fn {key, item} -> [key, canonical_value(item)] end)
    |> Enum.sort_by(&hd/1)
  end

  defp canonical_value(value) when is_list(value), do: Enum.map(value, &canonical_value/1)
  defp canonical_value(value), do: value
end
