defmodule GgenIgniter.ReviewEval.Corpus do
  @moduledoc """
  Incident-eval corpus: `.ggen_igniter/review-evals/corpus.jsonl`, one JSON
  object per line, schema_version 1.

  Case shape:

      %{
        "case_id" => "INC-001-abc1234",
        "schema_version" => 1,
        "source" => %{
          "kind" => "git_fix_commit",
          "ref" => "1a2b3c4",
          "receipt_citation" => nil,
          "commit_subject" => "fix(engine): ..."
        },
        "diff_ref" => %{"parent_sha" => "...", "fix_sha" => "..."},
        "defect" => %{
          "description" => "...",
          "invariant" => "...",
          "surfaces" => ["engine"]
        },
        "location" => %{"file" => "lib/.../foo.ex", "line" => 42, "line_tolerance" => 3},
        "provenance" => %{
          "seeded_at" => "...",
          "seed_command_version" => 1,
          "verified_in_fix" => true
        }
      }
  """

  @schema_version 1
  @default_tolerance 3

  @type t :: map()

  @spec schema_version() :: pos_integer()
  def schema_version, do: @schema_version

  @doc "Absolute path of the corpus file under the given repo root."
  @spec corpus_path(String.t()) :: String.t()
  def corpus_path(repo_root \\ "."),
    do: Path.join([repo_root, ".ggen_igniter", "review-evals", "corpus.jsonl"])

  @doc "Absolute path of the review-evals directory under the given repo root."
  @spec base_dir(String.t()) :: String.t()
  def base_dir(repo_root \\ "."),
    do: Path.join([repo_root, ".ggen_igniter", "review-evals"])

  @doc """
  Load cases from the corpus file. Returns `{:ok, cases}` (empty list when the
  file does not exist yet) or `{:error, term}` on an unparseable line
  (fail closed: the bad line number is reported).
  """
  @spec load(String.t()) :: {:ok, [map()]} | {:error, {:bad_line, pos_integer()}}
  def load(repo_root \\ ".") do
    path = corpus_path(repo_root)

    if File.exists?(path), do: load_file(path), else: {:ok, []}
  end

  defp load_file(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, &decode_line/2)
    |> case do
      {:ok, cases} -> {:ok, Enum.reverse(cases)}
      other -> other
    end
  end

  defp decode_line({line, n}, {:ok, acc}) do
    case Jason.decode(line) do
      {:ok, obj} -> {:cont, {:ok, [obj | acc]}}
      {:error, _} -> {:halt, {:error, {:bad_line, n}}}
    end
  end

  @doc """
  Write `cases` to the corpus file, replacing any prior content.
  Deterministic: case order as given, keys in structural order via Jason.
  """
  @spec write([map()], String.t()) :: :ok
  def write(cases, repo_root \\ ".") do
    path = corpus_path(repo_root)
    File.mkdir_p!(Path.dirname(path))

    body =
      cases
      |> Enum.map_join("\n", &Jason.encode!/1)
      |> Kernel.<>(if cases == [], do: "", else: "\n")

    File.write!(path, body)
    :ok
  end

  @doc "sha256 of the exact corpus file bytes (hex)."
  @spec digest(String.t()) :: String.t()
  def digest(repo_root \\ ".") do
    path = corpus_path(repo_root)

    if File.exists?(path) do
      Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
    else
      raise ArgumentError, "corpus not found at #{path}"
    end
  end

  @doc "Validate one decoded case object; returns :ok or {:error, reason}."
  @spec validate_case(map()) :: :ok | {:error, term()}
  def validate_case(%{
        "case_id" => id,
        "schema_version" => @schema_version,
        "source" => %{"kind" => kind} = _src,
        "diff_ref" => %{"parent_sha" => p, "fix_sha" => f},
        "defect" => %{"description" => _, "invariant" => _, "surfaces" => surfaces},
        "location" => %{"file" => file, "line" => line},
        "provenance" => _
      })
      when is_binary(id) and is_binary(p) and is_binary(f) and is_list(surfaces) and
             is_binary(file) and is_integer(line) do
    kind_atom = if is_binary(kind), do: String.to_atom(kind), else: kind

    if kind_atom in known_kinds() do
      :ok
    else
      {:error, {:unknown_source_kind, kind}}
    end
  end

  def validate_case(_), do: {:error, :invalid_case_shape}

  @doc "Known source.kind values."
  @spec known_kinds() :: [atom()]
  def known_kinds,
    do: [:git_fix_commit, :git_revert_receipt, :gall_doc, :verification_ledger, :manual]

  @doc "Default per-case line tolerance when location omits it."
  @spec default_tolerance() :: pos_integer()
  def default_tolerance, do: @default_tolerance
end
