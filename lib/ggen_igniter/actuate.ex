
defmodule GgenIgniter.Actuate do
  @moduledoc """
  v1: writes a rendered source string to a new file (greenfield case only). Igniter AST-patch actuation for incremental changes to an EXISTING file is an explicit, disclosed follow-on -- not implemented this pass (see pack.toml).
  """




  @doc "Writes `content` to `path`, creating parent directories as needed."
  @spec write_new_file!(String.t(), String.t()) :: :ok
  def write_new_file!(path, content) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end

end
