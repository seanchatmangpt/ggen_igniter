defmodule GgenIgniter.WriteOutcome do
  @moduledoc """
  Mirrors Rust `enum WriteOutcome { Written, Skipped(String), Injected }`
  (`~/ggen/crates/ggen-engine/src/write.rs:50-58`), and the `FM-WRITE-NNN`
  error-code convention (`write.rs:67-79,` `error.rs:194-197`).

  Note from the real Rust source (confirmed by review agent, not assumed):
  there is **no typed FM-WRITE-* enum** on the Rust side either -- the codes
  are numeric literals embedded in an `AppError::Validation(String)` message
  string via `AppError::fm_write(code, msg)`. This module mirrors that
  reality rather than inventing a typed enum the Rust side doesn't have: the
  codes are declared here as a plain map for reference/formatting only.

  `ggen_igniter`'s own `GgenIgniter.Actuate.write_file!/3` currently returns
  bare atoms (`:written` / `:unchanged` / `:skipped_exists` / `:skipped_match`)
  rather than this shape -- this module is the alignment target for a future
  pass that makes `Actuate` return `t:t/0` values instead, once the WASM
  bridge needs a shared wire format. Not wired into `Actuate` in this pass.
  """

  @type t :: :written | {:skipped, String.t()} | :injected

  @fm_write_codes %{
    1 => "root missing or not canonicalizable",
    2 => "path escapes root",
    3 => "inject target missing",
    4 => "inject marker not found / at_line out of bounds",
    5 => "differing content without force",
    6 => "checksum freeze without freeze_slots_dir",
    7 => "output exceeds MAX_OUTPUT_BYTES",
    8 => "invalid or oversized matcher"
  }

  @doc "Formats an `FM-WRITE-NNN` code + message the same way Rust's `AppError::fm_write/2` does."
  @spec format_fm_write_error(1..8, String.t() | nil) :: String.t()
  def format_fm_write_error(code, msg \\ nil) when code in 1..8 do
    code_str = code |> Integer.to_string() |> String.pad_leading(3, "0")
    "[FM-WRITE-#{code_str}] #{msg || Map.fetch!(@fm_write_codes, code)}"
  end

  @doc "Returns the known FM-WRITE-NNN code -> description map, for reference."
  @spec fm_write_codes() :: %{(1..8) => String.t()}
  def fm_write_codes, do: @fm_write_codes
end
