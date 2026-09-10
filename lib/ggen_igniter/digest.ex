defmodule GgenIgniter.Digest do
  @moduledoc """
  One shared `sha256` implementation, extracted after the same
  `:crypto.hash(:sha256, x) |> Base.encode16(case: :lower)` logic was found
  independently copy-pasted across `GgenIgniter.Manifest.hash_content/1`,
  `GgenIgniter.Pack`'s private `sha256_hex/1`, `GgenIgniter.Receipt`'s
  private `hex_sha256/1`, and `GgenIgniter.RuntimeShape.digest/1` (found in
  a v26.9.10 code-review pass; each callsite's own digest CONTENT is
  unchanged by this extraction, only where the hex-encoding logic lives).

  Two functions cover both real shapes those callers needed:
    * `hex/1` — the bare lowercase hex digest, no prefix (what
      `GgenIgniter.Pack` needed for its `hex.pm` checksum comparison).
    * `sha256/1` — the same digest with this codebase's `"sha256:" <> hex`
      prefix convention (what `GgenIgniter.Manifest`/`GgenIgniter.Receipt`/
      `GgenIgniter.RuntimeShape` all independently re-derived).
  """

  @doc "The lowercase hex-encoded SHA-256 digest of `binary`, no prefix."
  @spec hex(binary()) :: String.t()
  def hex(binary) when is_binary(binary) do
    :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)
  end

  @doc "This codebase's `\"sha256:\" <> hex` digest convention over `binary`."
  @spec sha256(binary()) :: String.t()
  def sha256(binary) when is_binary(binary) do
    "sha256:" <> hex(binary)
  end
end
