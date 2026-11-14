defmodule GgenIgniter.Convergence.Classes do
  @moduledoc """
  Closed vocabulary of review finding classes plus the class-fix operation:
  closing one class closes EVERY finding of that class across every file —
  a class typo is a typed refusal, never a silent bypass into "no matches,
  nothing fixed".
  """

  @classes [:formatting, :dead_code, :type_mismatch, :missing_doc, :test_gap, :naming]

  @typedoc "Closed set of review finding classes."
  @type class :: :formatting | :dead_code | :type_mismatch | :missing_doc | :test_gap | :naming

  @doc "The closed class-atom list."
  @spec classes() :: [class(), ...]
  def classes, do: @classes

  @doc """
  Closes all findings of `class` across all files: returns
  `{:ok, findings, count}` where every finding whose `class` matches is
  annotated `"reason" => "class_fixed"` (and removed from the open set by
  the caller). An atom not in the closed list returns
  `{:error, {:unknown_class, class}}` — a typo refuses, it does not
  no-op-through as an empty fix.

  `opts[:reason]` overrides the annotation reason (default `"class_fixed"`).
  """
  @spec apply_class_fix([map()], atom(), keyword()) ::
          {:ok, [map()], non_neg_integer()} | {:error, {:unknown_class, atom()}}
  def apply_class_fix(findings, class, opts \\ [])
      when is_list(findings) and is_atom(class) do
    if class in @classes do
      reason = Keyword.get(opts, :reason, "class_fixed")

      {fixed, count} =
        Enum.map_reduce(findings, 0, &annotate_if_class(&1, &2, class, reason))

      {:ok, fixed, count}
    else
      {:error, {:unknown_class, class}}
    end
  end

  defp annotate_if_class(finding, n, class, reason) do
    if Map.get(finding, :class) == class do
      {Map.put(finding, :reason, reason), n + 1}
    else
      {finding, n}
    end
  end
end
