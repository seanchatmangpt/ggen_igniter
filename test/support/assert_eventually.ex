defmodule GgenIgniterTest.AssertEventually do
  @moduledoc """
  The one audited bounded poll for tests (no-sleep doctrine).

  `eventually/2` re-evaluates a probe against a real observable until it
  returns a truthy value or a `System.monotonic_time/1` deadline passes. The
  sleep inside is the only test-side `Process.sleep/1` the sleep gate
  allowlists (`GgenIgniter.SleepGate`); call sites never sleep themselves.

  ## Examples

      iex> GgenIgniterTest.AssertEventually.eventually(fn -> :ready end)
      {:ok, :ready}

      iex> GgenIgniterTest.AssertEventually.eventually(fn -> false end, timeout: 30, step: 5)
      {:error, :timeout}
  """

  @default_timeout_ms 2_000
  @default_step_ms 25

  @doc """
  Polls `probe` until it returns a truthy value (`{:ok, value}`) or `:timeout`
  ms elapse (`{:error, :timeout}`). Options: `:timeout` (default 2000),
  `:step` (default 25). The probe runs at least once.
  """
  @spec eventually((-> term()), keyword()) :: {:ok, term()} | {:error, :timeout}
  def eventually(probe, opts \\ []) when is_function(probe, 0) do
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)
    step = Keyword.get(opts, :step, @default_step_ms)
    deadline = System.monotonic_time(:millisecond) + timeout
    poll(probe, step, deadline)
  end

  defp poll(probe, step, deadline) do
    case probe.() do
      falsy when falsy in [nil, false] ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, :timeout}
        else
          Process.sleep(step)
          poll(probe, step, deadline)
        end

      value ->
        {:ok, value}
    end
  end
end
