defmodule GgenIgniter.ParityTest do
  # Real ggen checkout + real Elixir struct; skips loudly (tagged) when ~/ggen is absent.
  use ExUnit.Case, async: true

  alias GgenIgniter.Parity

  @ggen Path.expand("~/ggen")
  @src Path.join(@ggen, "crates/ggen-engine/src/template.rs")

  @moduletag skip: if(File.exists?(@src), do: false, else: "ggen checkout absent: #{@src}")

  test "every Rust Frontmatter field is mirrored in the Elixir struct" do
    assert {:ok, rows} = Parity.check(ggen_dir: @ggen)
    assert length(rows) >= 25
    assert Enum.all?(rows, & &1.in_elixir)
    status = Map.new(rows, &{&1.field, &1.status})
    assert status[:skip_empty] == :pack_sync
    assert status[:backup] == :pack_sync
    assert status[:inject] == :mix_sync
    assert status[:construct] == :declared
    assert status[:envelope] == :internal
    assert status[:prefixes] == :declared
  end

  test "non-vacuous: a Rust field igniter lacks is reported as an error" do
    tmp = Path.join(System.tmp_dir!(), "parity_#{System.unique_integer([:positive])}")
    dir = Path.join(tmp, "crates/ggen-engine/src")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(tmp) end)

    File.write!(
      Path.join(dir, "template.rs"),
      File.read!(@src)
      |> String.replace(
        "pub struct Frontmatter {",
        "pub struct Frontmatter {\n    pub phantom_field: bool,"
      )
    )

    assert {:error, rows} = Parity.check(ggen_dir: tmp)
    assert [%{field: :phantom_field, in_elixir: false}] = Enum.reject(rows, & &1.in_elixir)
  end

  test "absent ggen checkout is a skip, never a pass" do
    assert {:skip, _} = Parity.check(ggen_dir: "/nonexistent/ggen")
  end
end
