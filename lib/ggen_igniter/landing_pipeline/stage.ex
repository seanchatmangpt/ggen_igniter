defmodule GgenIgniter.LandingPipeline.Stage do
  @moduledoc """
  The behaviour every landing-pipeline stage implements, plus the shared
  output-capture helpers stages use to embed REAL captured command output in
  their receipts.

  A stage is one named, ordered gate in `GgenIgniter.LandingPipeline.run/1`'s
  fixed registry (e.g. `GgenIgniter.LandingPipeline.Stage.EpochCheck` at
  order 1). The contract:

    * `name/0` — unique atom identifying the stage (receipt filenames,
      first-block reporting).
    * `order/0` — integer position in the fixed order. The order is
      LOAD-BEARING: risk tiering (order 2) runs before fan-out review
      (order 4) so review width is chosen only after the change has been
      classified — see the pipeline moduledoc.
    * `run/1` — receives a `%GgenIgniter.LandingPipeline.Stage.Context{}`
      (`base_sha`, `worktree_sha`, `paths`, `opts`) and returns exactly one
      of:

        * `{:pass, stage_receipt}` — gate held; the receipt MUST embed real
          captured output (see `capture/3`); a `:pass` whose embedded output
          is empty/absent is invalid and the pipeline will NOT report ALIVE
          on it.
        * `{:block, reason, stage_receipt}` — gate failed with a typed
          reason; the pipeline short-circuits.
        * `{:refused, reason}` — the stage cannot judge at all (missing
          substrate, unreadable input); the pipeline short-circuits.

  Stage modules are plain real modules — the pipeline resolves them with
  `Code.ensure_loaded/1` and a module that does not exist is a typed
  `{:stage_module_missing, name}` refusal, never a silent skip.
  """

  defstruct [:base_sha, :worktree_sha, :paths, :opts]

  @type t :: %__MODULE__{
          base_sha: String.t(),
          worktree_sha: String.t(),
          paths: [String.t()],
          opts: keyword()
        }

  @type stage_receipt :: %{
          optional(binary()) => term(),
          required(binary()) => term()
        }

  @callback name() :: atom()
  @callback order() :: integer()
  @callback run(t) :: {:pass, stage_receipt()} | {:block, reason :: term, stage_receipt()} | {:refused, reason :: term}

  @doc """
  Runs one real subprocess (`System.cmd/3`, list-args, stderr merged into
  stdout) and returns the embedded-output map the pipeline's realness law
  validates: `command`, `exit`, truncated `stdout_tail`, `duration_ms`.
  A stage `:pass` whose receipt does not embed at least one such map is
  rejected by `GgenIgniter.LandingPipeline` — a bare `:pass` proves nothing.
  """
  @spec capture(String.t(), [String.t()], keyword()) :: map()
  def capture(cmd, args, opts \\ []) do
    started = System.monotonic_time(:millisecond)

    {out, code} =
      System.cmd(cmd, args, stderr_to_stdout: true, cd: Keyword.get(opts, :cd, File.cwd!()))

    %{
      "command" => Enum.join([cmd | args], " "),
      "exit" => code,
      "stdout_tail" => tail(out, Keyword.get(opts, :tail, 2000)),
      "duration_ms" => System.monotonic_time(:millisecond) - started
    }
  end

  @doc """
  Truncates captured output to its LAST `max` characters (the tail is what
  carries the verdict line of a failing command).
  """
  @spec tail(String.t(), pos_integer()) :: String.t()
  def tail(out, max \\ 2000) when is_binary(out) and max > 0 do
    if String.length(out) > max do
      "…" <> String.slice(out, -max..-1//1)
    else
      out
    end
  end

  @doc """
  The git blob sha of one file (`git hash-object <path>`) — the content
  identity a stage receipt embeds "where applicable". Fails loudly
  (FileError-free `{:error, reason}`) rather than inventing a sha.
  """
  @spec blob_sha(String.t()) :: {:ok, String.t()} | {:error, term()}
  def blob_sha(path) do
    case System.cmd("git", ["hash-object", path], stderr_to_stdout: true) do
      {sha, 0} -> {:ok, String.trim(sha)}
      {out, _} -> {:error, {:blob_sha_failed, path, String.trim(out)}}
    end
  end
end
