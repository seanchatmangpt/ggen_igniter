defmodule RealDir do
  @moduledoc """
  Resolves the real (symlink-free) absolute path of an existing directory.

  Why not `:file.realpath/1`: it exists only from OTP 28, and this repo
  pins OTP 27. The case that matters is the macOS TMPDIR symlink
  (`/var/folders/...` -> `/private/var/folders/...`): the manifest /
  actuation / canonicalize layers store realpath'd keys, so scratch dirs
  handed to them by tests must be expressed in the same real form for
  expectations to compare equal. `pwd -P` gives exactly that on both
  macOS and Linux.
  """

  @spec real_dir!(Path.t()) :: Path.t()
  def real_dir!(dir) when is_binary(dir) do
    {real, 0} = System.cmd("sh", ["-c", "pwd -P"], cd: dir)
    String.trim_trailing(real, "\n")
  end
end
