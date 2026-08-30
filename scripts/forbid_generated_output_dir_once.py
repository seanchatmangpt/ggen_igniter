from pathlib import Path


def insert_after_line(lines: list[str], predicate, insertion: str, label: str) -> list[str]:
    if insertion in lines:
        return lines
    for index, line in enumerate(lines):
        if predicate(line):
            return lines[: index + 1] + [insertion] + lines[index + 1 :]
    raise SystemExit(f"anchor not found: {label}")


actuate_path = Path("lib/ggen_igniter/actuate.ex")
actuate = actuate_path.read_text()

doc_anchor = "  Igniter AST-patch actuation (a real `Sourceror`/`Igniter.Code`-based\n"
policy_doc = """  ## Reserved `generated/` directory invariant

  A directory path segment named exactly `generated` is a forbidden output
  ownership surface. Generated projections must land at their canonical source
  location (for example `lib/my_app/accounts/user.ex`), not under a parallel
  `generated/` tree. This is fail-closed across all three filesystem actuation
  paths below, including `--dry-run`: the path is canonicalized first so `.`/`..`
  aliases and existing symlink aliases cannot bypass the refusal. A filename such
  as `generated_file.ex` is valid; only a directory segment named `generated` is
  reserved.

"""
if policy_doc not in actuate:
    if doc_anchor not in actuate:
        raise SystemExit("actuate moduledoc anchor not found")
    actuate = actuate.replace(doc_anchor, policy_doc + doc_anchor, 1)

lines = actuate.splitlines(keepends=True)
lines = insert_after_line(
    lines,
    lambda line: line.startswith("  def write_new_file!(path, content) do"),
    "    refuse_generated_directory!(path)\n",
    "write_new_file!/2",
)
lines = insert_after_line(
    lines,
    lambda line: line.startswith("  def write_file!(path, content, opts "),
    "    refuse_generated_directory!(path)\n",
    "write_file!/3",
)

if "    refuse_generated_directory!(path)\n" not in lines[
    max(0, next((i for i, line in enumerate(lines) if line.startswith("  def inject_content!(")), 0)) :
]:
    for index, line in enumerate(lines):
        if line.strip() == "when insert_mode in [:before, :after, :at_line] do":
            lines.insert(index + 1, "    refuse_generated_directory!(path)\n")
            break
    else:
        raise SystemExit("anchor not found: inject_content!/5")

actuate = "".join(lines)

helper_anchor = "  defp matches?(content, %Regex{} = pattern), do: Regex.match?(pattern, content)\n"
helper = """  # Fail-closed output policy shared by every filesystem actuation path.
  # Canonicalization resolves lexical aliases and existing symlink aliases before
  # checking the project-relative path for the reserved directory segment.
  defp refuse_generated_directory!(path) do
    cwd = File.cwd!()
    canonical_root = GgenIgniter.ArtifactIdentity.canonicalize(cwd, ".")
    canonical_target = GgenIgniter.ArtifactIdentity.canonicalize(cwd, path)
    relative_target = Path.relative_to(canonical_target, canonical_root)

    if Enum.member?(Path.split(relative_target), "generated") do
      raise ArgumentError,
            "REFUSED generated_directory: output path #{inspect(path)} resolves through " <>
              "a reserved `generated/` directory (#{inspect(canonical_target)}). " <>
              "Write the projection to its canonical source location instead."
    end

    :ok
  end

"""
if helper not in actuate:
    if helper_anchor not in actuate:
        raise SystemExit("actuate helper anchor not found")
    actuate = actuate.replace(helper_anchor, helper + helper_anchor, 1)

actuate_path.write_text(actuate)

for path_str in ["README.md", "lib/mix/tasks/ggen_igniter.sync.ex"]:
    path = Path(path_str)
    text = path.read_text()
    text = text.replace(
        'lib/generated/<%= module_name %>.ex',
        'lib/<%= Macro.underscore(module_name) %>.ex',
    )
    text = text.replace('lib/generated/Multi.Alpha.ex', 'lib/multi/alpha.ex')
    text = text.replace('lib/generated/Multi.Beta.ex', 'lib/multi/beta.ex')
    text = text.replace('lib/generated/Multi.Gamma.ex', 'lib/multi/gamma.ex')
    text = text.replace('lib/generated/resource.ex', 'lib/my_app/resources/resource.ex')
    text = text.replace('lib/generated.ex', 'lib/my_app/extension.ex')
    path.write_text(text)

test_path = Path("test/generated_directory_policy_test.exs")
test_path.write_text(
    r'''defmodule GgenIgniter.GeneratedDirectoryPolicyTest do
  @moduledoc """
  Chicago-style: real temporary directories, real files, a real filesystem
  symlink, and the real `GgenIgniter.Actuate` write/injection functions prove
  that a canonical directory segment named `generated` is refused before any
  mutation while similarly named files remain writable.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.Actuate

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_generated_dir_policy_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(root)
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  describe "filesystem actuation generated/ refusal" do
    test "write_new_file!/2 refuses a generated directory before creating anything", %{root: root} do
      path = Path.join([root, "lib", "generated", "widget.ex"])

      assert_raise ArgumentError, ~r/REFUSED generated_directory/, fn ->
        Actuate.write_new_file!(path, "defmodule Widget, do: :ok\n")
      end

      refute File.exists?(path)
      refute File.exists?(Path.dirname(path))
    end

    test "write_file!/3 refuses generated directories even under dry-run", %{root: root} do
      path = Path.join([root, "lib", "generated", "widget.ex"])

      assert_raise ArgumentError, ~r/REFUSED generated_directory/, fn ->
        Actuate.write_file!(path, "defmodule Widget, do: :ok\n", dry_run: true)
      end

      refute File.exists?(path)
    end

    test "inject_content!/5 refuses an existing target under generated before mutation", %{root: root} do
      path = Path.join([root, "lib", "generated", "host.ex"])
      File.mkdir_p!(Path.dirname(path))
      original = "defmodule Host do\n  # ggen:slot\nend\n"
      File.write!(path, original)

      assert_raise ArgumentError, ~r/REFUSED generated_directory/, fn ->
        Actuate.inject_content!(path, "# ggen:slot", "  def projected, do: :ok", :after)
      end

      assert File.read!(path) == original
    end

    test "canonicalization prevents a real symlink alias from bypassing the refusal", %{root: root} do
      generated_dir = Path.join(root, "generated")
      alias_dir = Path.join(root, "projection_alias")
      File.mkdir_p!(generated_dir)
      File.ln_s!(generated_dir, alias_dir)
      path = Path.join(alias_dir, "widget.ex")

      assert_raise ArgumentError, ~r/REFUSED generated_directory/, fn ->
        Actuate.write_file!(path, "defmodule Widget, do: :ok\n")
      end

      refute File.exists?(Path.join(generated_dir, "widget.ex"))
    end

    test "a filename containing generated remains valid", %{root: root} do
      path = Path.join([root, "lib", "generated_file.ex"])

      assert {:ok, :written} =
               Actuate.write_file!(path, "defmodule GeneratedFile, do: :ok\n")

      assert File.read!(path) == "defmodule GeneratedFile, do: :ok\n"
    end
  end
end
'''
)
