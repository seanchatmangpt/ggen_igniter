defmodule GgenIgniter.SecurityReview.Receipt do
  @moduledoc """
  The findings ledger for the security gate: stable finding ids, a
  deterministic JSON ledger at `<cwd>/.ggen_igniter/security-findings.json`,
  per-commit sealed copies at `<cwd>/receipts/security/<short-sha>.json`, and
  the auto-clear transition.

  * **Stable id** — `"SEC-" <> upcase(category) <> "-" <> first8(hex(sha256(
    category|file|rule|normalized_evidence)))`. Normalization collapses every
    whitespace run to one space and trims, so a reformat or line renumbering
    leaves the id (and therefore the ledger's continuity) untouched; `line`
    is deliberately NOT part of the id.
  * **Determinism** — every JSON write goes through
    `GgenIgniter.TaskContract.encode/1` (recursively key-sorted), so two runs
    over the same diff produce byte-identical files.
  * **Auto-clear** — a previously `open` finding whose id is absent from the
    current set becomes `auto_cleared` with `cleared_at_commit` set. A
    `cleared` id never resurrects: if the same defect reappears later it is
    still recorded `auto_cleared` (the human clear decision is a fact about
    the code, not something a re-diff overrides).
  * **Verdict** — `status: "blocked"` iff any finding in the returned ledger
    is `open`.
  """

  @ledger_path Path.join(".ggen_igniter", "security-findings.json")
  @sealed_dir Path.join("receipts", "security")

  @doc "Collapses whitespace runs to single spaces and trims — the id-stable evidence form."
  @spec normalize_evidence(String.t()) :: String.t()
  def normalize_evidence(evidence) when is_binary(evidence) do
    evidence
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  @doc """
  The stable finding id: `SEC-<CATEGORY>-<first8>` where the hash input is
  `category|file|rule|normalized_evidence`. Line numbers are excluded so the
  id survives line renumbering.
  """
  @spec finding_id(%{
          category: String.t(),
          file: String.t(),
          rule: String.t(),
          evidence: String.t()
        }) ::
          String.t()
  def finding_id(%{category: category, file: file, rule: rule, evidence: evidence}) do
    payload =
      Enum.join(
        [category, file, rule, normalize_evidence(evidence)],
        "|"
      )

    <<digest::binary-size(4), _rest::binary>> = :crypto.hash(:sha256, payload)
    "SEC-" <> String.upcase(category) <> "-" <> Base.encode16(digest, case: :lower)
  end

  @doc """
  Merges `new_findings` (plain maps from the checks) with the previous
  ledger at `<cwd>/.ggen_igniter/security-findings.json`, writes the updated
  ledger plus the sealed per-commit copy, and returns the receipt map
  (`%{"commit" => ..., "findings" => [...], "open_count" => ...,
  "status" => "blocked" | "clear"}`). Deterministic: identical inputs give
  byte-identical files.
  """
  @spec write([map()], String.t(), String.t() | nil) :: map()
  def write(new_findings, cwd, commit) do
    ledger_file = Path.join(cwd, @ledger_path)
    previous = load_previous(ledger_file)
    receipt = compute(new_findings, previous, commit)

    File.mkdir_p!(Path.join(cwd, Path.dirname(@ledger_path)))

    File.write!(ledger_file, GgenIgniter.TaskContract.encode(receipt) <> "\n")

    if commit do
      seal(receipt, cwd, commit)
    end

    receipt
  end

  @doc """
  The pure, side-effect-free core of `write/3`: merges `new_findings` with
  the `previous` ledger entries and returns the receipt map WITHOUT writing
  anything. `--check` (read mode) and tests use this; `write/3` delegates
  its merge here and then persists.
  """
  @spec compute([map()], [map()], String.t() | nil) :: map()
  def compute(new_findings, previous, commit) do
    cleared_ids = previously_cleared_ids(previous)

    now =
      Enum.map(new_findings, fn f ->
        id = finding_id(f)
        prior = Enum.find(previous, &(&1["id"] == id))

        if prior do
          %{
            "id" => id,
            "category" => f.category,
            "file" => f.file,
            "rule" => f.rule,
            "severity" => to_string(f.severity),
            "evidence" => f.evidence,
            "line" => Map.get(f, :line),
            "state" => prior["state"],
            "first_seen_commit" => prior["first_seen_commit"] || commit
          }
        else
          %{
            "id" => id,
            "category" => f.category,
            "file" => f.file,
            "rule" => f.rule,
            "severity" => to_string(f.severity),
            "evidence" => f.evidence,
            "line" => Map.get(f, :line),
            "state" => "open",
            "first_seen_commit" => commit
          }
        end
        |> maybe_force_cleared(cleared_ids)
      end)

    current_ids = MapSet.new(now, & &1["id"])

    auto_cleared =
      for f <- previous,
          f["state"] == "open",
          not MapSet.member?(current_ids, f["id"]) do
        f
        |> Map.put("state", "auto_cleared")
        |> Map.put("cleared_at_commit", commit)
      end

    findings = Enum.sort_by(now ++ auto_cleared, & &1["id"])

    %{
      "commit" => commit,
      "findings" => findings,
      "open_count" => Enum.count(findings, &(&1["state"] == "open")),
      "status" => if(Enum.any?(findings, &(&1["state"] == "open")), do: "blocked", else: "clear")
    }
  end

  # A previously-cleared id stays cleared even when the same defect
  # reappears — cleared never resurrects.
  defp maybe_force_cleared(finding, cleared_ids) do
    if MapSet.member?(cleared_ids, finding["id"]) do
      finding
      |> Map.put("state", "auto_cleared")
      |> Map.put("cleared_at_commit", finding["first_seen_commit"])
    else
      finding
    end
  end

  defp previously_cleared_ids(previous) do
    previous
    |> Enum.filter(&(&1["state"] == "auto_cleared"))
    |> Enum.map(& &1["id"])
    |> MapSet.new()
  end

  @doc "Reads the previous ledger entries at `<cwd>/.ggen_igniter/security-findings.json` ([] when absent/unparsable — a corrupt ledger never fabricates findings)."
  @spec read_ledger(String.t()) :: [map()]
  def read_ledger(cwd), do: load_previous(Path.join(cwd, @ledger_path))

  defp load_previous(ledger_file) do
    case File.read(ledger_file) do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, %{"findings" => findings}} when is_list(findings) -> findings
          _ -> []
        end

      {:error, _} ->
        []
    end
  end

  # The sealed copy is the audit trail: one immutable JSON snapshot per
  # commit SHA that ever ran the gate.
  defp seal(receipt, cwd, commit) do
    sealed_dir = Path.join(cwd, @sealed_dir)
    File.mkdir_p!(sealed_dir)
    short = String.slice(commit, 0, 8)
    File.write!(Path.join(sealed_dir, short <> ".json"), GgenIgniter.TaskContract.encode(receipt))
  end
end
