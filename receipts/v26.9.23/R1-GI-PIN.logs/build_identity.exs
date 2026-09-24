# usage (repo root, under the pin): elixir receipts/v26.9.23/R1-GI-PIN.logs/build_identity.exs
# Prints the compiler (OTP) identity of the beams in _build/{dev,test} for ggen_igniter, jason and
# ash_a2a (first beam of each ebin, sorted), then the running otp_release / erts / compiler app.
for env <- ["dev", "test"], app <- ["ggen_igniter", "jason", "ash_a2a"] do
  ebin = Path.join(["_build", env, "lib", app, "ebin"])
  beam = ebin |> File.ls!() |> Enum.filter(&String.ends_with?(&1, ".beam")) |> Enum.sort() |> hd()

  {:ok, {_, [compile_info: info]}} =
    :beam_lib.chunks(String.to_charlist(Path.join(ebin, beam)), [:compile_info])

  IO.puts("#{env} #{app} #{beam} compiler=#{info[:version]}")
end

_ = Application.load(:compiler)

IO.puts(
  "otp_release=#{:erlang.system_info(:otp_release)} erts=#{:erlang.system_info(:version)} " <>
    "compiler_app=#{Application.spec(:compiler, :vsn)}"
)
