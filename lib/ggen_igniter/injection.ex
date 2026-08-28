defmodule GgenIgniter.Injection do
  @moduledoc """
  Shared frontmatter-`inject:`-to-`GgenIgniter.Actuate.inject_content!/5`
  conversion logic, extracted so `Mix.Tasks.GgenIgniter.Sync` (the original,
  standalone pipeline) and `GgenIgniter.Reactors.ReconcileReactor` (the
  opt-in Reactor pipeline) share exactly ONE real implementation instead of
  two independently-drifting copies -- see this module's functions'
  individual docs for the full mapping table (originally authored inline in
  `Mix.Tasks.GgenIgniter.Sync`, moved here verbatim, behavior unchanged).

  Two real entry points:

    * `resolve_injection!/1` -- converts a `GgenIgniter.Frontmatter.t()`'s
      `inject:`/`before:`/`after:`/`at_line:` fields into
      `{marker, insert_mode, insert_opts}`, `Actuate.inject_content!/5`'s
      real `marker`/`insert_mode`/`opts` args (minus `path`/`content`,
      which are call-site-specific). Requires exactly one of
      `before:`/`after:`/`at_line:` -- zero or more than one raises a
      clear, named `ArgumentError` (a template-authoring error, never a
      silent pick).
    * `strip_single_trailing_newline/1` -- strips exactly one trailing
      `"\\n"` from a rendered injection body before it reaches
      `Actuate.inject_content!/5`, which otherwise splices in one real
      extra blank line (mirrors `Actuate`'s own trailing-newline handling
      for the TARGET file's lines).
  """

  alias GgenIgniter.Frontmatter
  alias GgenIgniter.Frontmatter.MatchRule

  @doc """
  Converts a template's `inject:`/`before:`/`after:`/`at_line:` frontmatter
  fields into `Actuate.inject_content!/5`'s real args
  (`{marker, insert_mode, insert_opts}`). Exactly one anchor is required --
  `before` OR `after` OR `at_line`, never zero, never more than one.
  """
  @spec resolve_injection!(Frontmatter.t()) ::
          {String.t() | Regex.t() | nil, :before | :after | :at_line, keyword()}
  def resolve_injection!(%Frontmatter{} = frontmatter) do
    anchors =
      [before: frontmatter.before, after: frontmatter.after, at_line: frontmatter.at_line]
      |> Enum.filter(fn {_k, v} -> v != nil end)

    case anchors do
      [] ->
        raise ArgumentError,
              "template frontmatter has \"inject: true\" but none of before:/after:/at_line: " <>
                "is set -- injection requires exactly one anchor"

      [{:before, spec}] ->
        {match_spec_to_marker!(spec, "before"), :before, []}

      [{:after, spec}] ->
        {match_spec_to_marker!(spec, "after"), :after, []}

      [{:at_line, at_line}] ->
        {nil, :at_line, [line: at_line]}

      many ->
        names = Enum.map_join(many, ", ", fn {k, _v} -> "#{k}:" end)

        raise ArgumentError,
              "template frontmatter has \"inject: true\" but more than one anchor is set " <>
                "(#{names}) -- injection requires exactly one of before:/after:/at_line:"
    end
  end

  # Converts a `GgenIgniter.Frontmatter.MatchSpec.t()` into whatever
  # `Actuate.inject_content!/5`'s real `marker` arg expects
  # (`String.t() | Regex.t()`). See this module's moduledoc for the full
  # mapping table; what is genuinely NOT implemented against
  # `inject_content!/5`'s real anchor-resolution behavior raises a clear,
  # honest error naming the exact unsupported combination, rather than
  # silently proceeding as if it had been honored.
  @spec match_spec_to_marker!(Frontmatter.MatchSpec.t(), String.t()) :: String.t() | Regex.t()
  defp match_spec_to_marker!({:literal, s}, _label), do: s

  defp match_spec_to_marker!({:structured, %MatchRule{} = rule}, label) do
    if rule.scope == :file do
      unsupported_match_rule!(
        label,
        "scope: :file",
        "inject_content!/5 only matches a marker against individual lines, never across " <>
          "the whole file"
      )
    end

    if rule.occurrence != :first do
      unsupported_match_rule!(
        label,
        "occurrence: #{inspect(rule.occurrence)}",
        "inject_content!/5 always requires the marker to match exactly one line (raising on " <>
          "zero or on more than one match) -- it has no concept of selecting a specific " <>
          "occurrence (last/unique/nth) among several matches; only occurrence: :first " <>
          "(the default) maps onto that real behavior"
      )
    end

    if rule.trim and rule.matcher != :exact do
      unsupported_match_rule!(
        label,
        "trim: true with matcher: #{inspect(rule.matcher)}",
        "trim is only implemented for matcher: :exact"
      )
    end

    build_regex_marker(rule)
  end

  defp unsupported_match_rule!(label, option, reason) do
    raise ArgumentError,
          "template frontmatter's structured #{label}: rule sets #{option}, which is not yet " <>
            "supported by ggen_igniter's injection engine (Actuate.inject_content!/5): #{reason}"
  end

  defp build_regex_marker(%MatchRule{matcher: :contains, pattern: pattern, case_sensitive: true}),
    do: pattern

  defp build_regex_marker(%MatchRule{
         matcher: :contains,
         pattern: pattern,
         case_sensitive: false
       }),
       do: compile_regex!(Regex.escape(pattern), false)

  defp build_regex_marker(%MatchRule{
         matcher: :exact,
         pattern: pattern,
         case_sensitive: case_sensitive,
         trim: trim
       }) do
    escaped = Regex.escape(pattern)
    source = if trim, do: "^\\s*#{escaped}\\s*$", else: "^#{escaped}$"
    compile_regex!(source, case_sensitive)
  end

  defp build_regex_marker(%MatchRule{matcher: :regex, pattern: pattern, case_sensitive: cs}),
    do: compile_regex!(pattern, cs)

  defp compile_regex!(source, case_sensitive?) do
    flags = if case_sensitive?, do: "", else: "i"
    Regex.compile!(source, flags)
  end

  @doc """
  A rendered template body ends in a trailing `"\\n"` as a plain
  file-formatting convention -- but `Actuate.inject_content!/5` itself does
  `String.split(content, "\\n")` un-trimmed, so an un-stripped trailing
  `"\\n"` would splice in one real extra blank line at the end of the
  injected block. Strips exactly one trailing `"\\n"` (mirroring
  `Actuate`'s own `drop_trailing_empty/1` for the TARGET file's lines),
  without guessing at or discarding any blank lines the template author put
  there deliberately (a second trailing blank line in the template body is
  left fully intact).
  """
  @spec strip_single_trailing_newline(String.t()) :: String.t()
  def strip_single_trailing_newline(content) do
    case String.split(content, "\n") do
      [_single] ->
        content

      parts ->
        case List.last(parts) do
          "" -> parts |> List.delete_at(-1) |> Enum.join("\n")
          _ -> content
        end
    end
  end
end
