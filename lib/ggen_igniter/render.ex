
defmodule GgenIgniter.Render do
  @moduledoc """
  Renders an EEx template string against query-result bindings into a final source-code string. Stdlib EEx, not a Tera/Liquid port -- see pack.toml for why.
  """




  @doc "Evaluates `template_string` as EEx with `bindings` (a keyword list or map with atom keys) in scope, returning the rendered source string."
  @spec render(String.t(), keyword() | map()) :: String.t()
  def render(template_string, bindings) do
    bindings = if is_map(bindings), do: Map.to_list(bindings), else: bindings
    EEx.eval_string(template_string, bindings)
  end

end
