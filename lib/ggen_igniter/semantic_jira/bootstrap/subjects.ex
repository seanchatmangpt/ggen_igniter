defmodule GgenIgniter.SemanticJira.Bootstrap.Subjects do
  @moduledoc """
  Current subjects of the cold bootstrap (GC23-1): which repositories exist,
  which checkout is under judgement for each, and its exact `HEAD`.

  Sources, in order of authority:

    * the fleet file -- either a GC23-11 fleet matrix (`matrix.ttl`,
      `sj:FleetMatrixRow` rows read by `bootstrap/fleet.rq`: name, local
      path, `sj:fleetClass`, `sj:requiredForCheckpoint`, recorded
      `sj:observedSha`) or a fleet universe (`universe.json`:
      `repositories[]` with `name`, `github`, `path`, `fleet_role`);
    * explicit `--checkout owner/repo=DIR` configuration, which names the
      checkout under judgement and overrides the fleet path.

  Live `HEAD`s are observed (`git -C`) for every `--checkout`, for every
  fleet-matrix row required by the checkpoint and for every universe row;
  a matrix row not required by the checkpoint keeps only its recorded SHA
  (bounded state: PRD section 10 makes every-repo-ALIVE a non-goal, and a
  concurrently moving non-required repo must not perturb the reconstruction).
  A fleet row whose path is forbidden (`Guard.forbidden_path/1`) is never
  read; it is reported `refused(forbidden_path)`.

  Local paths never leave this module: the state carries repository names,
  SHAs and branches only.
  """

  alias GgenIgniter.SemanticJira.Bootstrap.{Git, Guard}

  @type subject :: %{
          required(:repository) => String.t(),
          required(:name) => String.t(),
          optional(atom()) => term()
        }

  @doc """
  Builds the subjects from fleet rows (`:matrix` or `:universe` form) and
  `[{repository, dir}]` checkouts. Returns subjects sorted by repository.
  """
  @spec build({:matrix | :universe, [map()]}, [{String.t(), Path.t()}]) :: [subject()]
  def build({form, rows}, checkouts) do
    fleet = Enum.map(rows, &fleet_subject(form, &1))

    {merged, unmatched} =
      Enum.reduce(checkouts, {fleet, []}, fn {repository, dir}, {subjects, extra} ->
        case Enum.find_index(subjects, &same_repository?(&1, repository)) do
          nil ->
            {subjects, [checkout_subject(repository, dir) | extra]}

          index ->
            {List.update_at(subjects, index, &override(&1, repository, dir)), extra}
        end
      end)

    (merged ++ unmatched)
    |> Enum.map(&observe/1)
    |> Enum.sort_by(& &1.repository)
  end

  defp fleet_subject(:matrix, row) do
    %{
      repository: row.name,
      name: row.name,
      source: "fleet",
      class: row.class,
      required: row.required,
      recorded_sha: row.recorded_sha,
      dir: row.path,
      live?: row.required
    }
  end

  defp fleet_subject(:universe, row) do
    %{
      repository: row["github"] || row["name"],
      name: row["name"] || row["github"],
      source: "fleet",
      class: row["fleet_role"],
      required: nil,
      recorded_sha: nil,
      dir: row["path"],
      live?: true
    }
  end

  defp checkout_subject(repository, dir) do
    %{
      repository: repository,
      name: repository |> String.split("/") |> List.last(),
      source: "checkout",
      class: nil,
      required: nil,
      recorded_sha: nil,
      dir: dir,
      live?: true
    }
  end

  defp override(subject, repository, dir),
    do: %{subject | repository: repository, source: "checkout", dir: dir, live?: true}

  @doc "True when `subject` is the repository `owner/repo` (or its bare name)."
  @spec same_repository?(map(), String.t()) :: boolean()
  def same_repository?(subject, repository) do
    subject.repository == repository or
      subject.name == repository |> String.split("/") |> List.last()
  end

  defp observe(%{live?: false} = subject), do: finish(subject, %{status: "recorded"})

  defp observe(%{dir: dir} = subject) when not is_binary(dir),
    do: finish(subject, %{status: "absent"})

  defp observe(%{dir: dir} = subject) do
    cond do
      reason = Guard.forbidden_path(dir) ->
        finish(subject, %{status: "refused(forbidden_path)", refusal: reason})

      not File.dir?(dir) ->
        finish(subject, %{status: "absent"})

      true ->
        observe_git(subject, dir)
    end
  end

  defp observe_git(subject, dir) do
    with {:ok, top} <- Git.toplevel(dir),
         {:ok, head} <- Git.head(top) do
      finish(subject, %{
        status: "observed",
        head_sha: head,
        branch: Git.branch(top),
        toplevel: top,
        real_toplevel: Guard.real_path(top)
      })
    else
      :error -> finish(subject, %{status: "not_a_git_repository"})
    end
  end

  defp finish(subject, observed), do: subject |> Map.delete(:live?) |> Map.merge(observed)

  @doc "The observed subject for an order's `owner/repo`, or `nil`."
  @spec for_repository([subject()], String.t() | nil) :: subject() | nil
  def for_repository(_subjects, nil), do: nil

  def for_repository(subjects, repository) do
    Enum.find(subjects, &(&1.status == "observed" and &1.repository == repository)) ||
      Enum.find(subjects, &(&1.status == "observed" and same_repository?(&1, repository)))
  end

  @doc """
  A host-independent reference for an input path: `owner/repo:relative/path`
  when the path lies inside an observed checkout, else `<role>:<basename>`.
  """
  @spec ref([subject()], Path.t(), String.t()) :: String.t()
  def ref(subjects, path, role) do
    real = Guard.real_path(path)

    subjects
    |> Enum.filter(&(&1.status == "observed"))
    |> Enum.sort_by(&(-byte_size(&1.real_toplevel)))
    |> Enum.find_value(fn subject ->
      relative = Path.relative_to(real, subject.real_toplevel)

      cond do
        real == subject.real_toplevel -> subject.repository <> ":."
        relative != real -> subject.repository <> ":" <> relative
        true -> nil
      end
    end)
    |> Kernel.||(role <> ":" <> Path.basename(path))
  end

  @doc "The JSON form of a subject (no local paths)."
  @spec to_json(subject()) :: map()
  def to_json(subject) do
    %{
      "repository" => subject.repository,
      "name" => subject.name,
      "source" => subject.source,
      "class" => subject.class,
      "required" => subject.required,
      "recorded_sha" => subject.recorded_sha,
      "status" => subject.status,
      "head_sha" => Map.get(subject, :head_sha),
      "branch" => Map.get(subject, :branch)
    }
  end
end
