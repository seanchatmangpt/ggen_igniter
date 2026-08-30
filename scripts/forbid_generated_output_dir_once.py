from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f"anchor not found: {label}")
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# Actuation boundary: shared typed policy + defense-in-depth refusal.
# ---------------------------------------------------------------------------
actuate_path = Path("lib/ggen_igniter/actuate.ex")
actuate = actuate_path.read_text()

doc_anchor = "  Igniter AST-patch actuation (a real `Sourceror`/`Igniter.Code`-based\n"
policy_doc = """  ## Reserved `generated/` directory invariant

  A directory path segment named exactly `generated` is a forbidden output
  ownership surface. Generated projections must land at their canonical source
  location (for example `lib/my_app/accounts/user.ex`), not under a parallel
  `generated/` tree. The path is canonicalized before admission, so `.`/`..`
  aliases and existing symlink aliases cannot bypass the refusal. A filename
  such as `generated_file.ex` is valid; only a directory segment named exactly
  `generated` is reserved.

  `output_path_admission/1` is the typed, side-effect-free policy used by the
  whole-plan admission layer. `admit_output_path!/1` is the fail-closed
  actuation-boundary form. Every filesystem mutation path calls the latter as
  defense in depth, but callers that own a multi-output plan MUST preflight the
  full plan before the first write.

"""
if policy_doc not in actuate:
    if doc_anchor not in actuate:
        raise SystemExit("actuate moduledoc anchor not found")
    actuate = actuate.replace(doc_anchor, policy_doc + doc_anchor, 1)

for signature in [
    "  def write_new_file!(path, content) do\n",
    "  def write_file!(path, content, opts \\\\ []) do\n",
]:
    insertion = signature + "    admit_output_path!(path)\n"
    if insertion not in actuate:
        if signature not in actuate:
            raise SystemExit(f"actuate function anchor not found: {signature.strip()}")
        actuate = actuate.replace(signature, insertion, 1)

inject_anchor = (
    "  def inject_content!(path, marker, content, insert_mode, opts \\\\ [])\n"
    "      when insert_mode in [:before, :after, :at_line] do\n"
)
inject_with_guard = inject_anchor + "    admit_output_path!(path)\n"
if inject_with_guard not in actuate:
    if inject_anchor not in actuate:
        raise SystemExit("actuate function anchor not found: inject_content!/5")
    actuate = actuate.replace(inject_anchor, inject_with_guard, 1)

helper_anchor = "  defp matches?(content, %Regex{} = pattern), do: Regex.match?(pattern, content)\n"
helpers = '''  @doc """
  Pure admission check for one output path.

  Returns a typed refusal when the canonical target resolves through any
  directory segment named exactly `generated`. Existing symlink aliases are
  resolved by `ArtifactIdentity.canonicalize/2` before the directory-segment
  check. The final path component is deliberately excluded so a file named
  `generated` (or `generated_file.ex`) is not confused with a directory.
  """
  @spec output_path_admission(String.t()) ::
          :ok | {:error, {:refused_generated_directory, String.t()}}
  def output_path_admission(path) when is_binary(path) do
    canonical_target = GgenIgniter.ArtifactIdentity.canonicalize(File.cwd!(), path)

    if canonical_target
       |> Path.dirname()
       |> Path.split()
       |> Enum.member?("generated") do
      {:error, {:refused_generated_directory, canonical_target}}
    else
      :ok
    end
  end

  @doc """
  Fail-closed actuation-boundary form of `output_path_admission/1`.
  """
  @spec admit_output_path!(String.t()) :: :ok
  def admit_output_path!(path) when is_binary(path) do
    case output_path_admission(path) do
      :ok ->
        :ok

      {:error, {:refused_generated_directory, canonical_target}} ->
        raise ArgumentError,
              "REFUSED generated_directory: output path #{inspect(path)} resolves through " <>
                "a reserved `generated/` directory (#{inspect(canonical_target)}). " <>
                "Write the projection to its canonical source location instead."
    end
  end

'''
if helpers not in actuate:
    if helper_anchor not in actuate:
        raise SystemExit("actuate helper anchor not found")
    actuate = actuate.replace(helper_anchor, helpers + helper_anchor, 1)

actuate_path.write_text(actuate)


# ---------------------------------------------------------------------------
# Direct sync pipeline: preflight EVERY rendered output before first actuation.
# ---------------------------------------------------------------------------
sync_path = Path("lib/mix/tasks/ggen_igniter.sync.ex")
sync = sync_path.read_text()

render_anchor = '''    renders =
      Enum.map(rows, fn row ->
        bindings = build_bindings(named_results, row)
        content = Render.render(template_string, bindings)
        out_path = if out_template, do: Render.render(out_template, bindings)
        {bindings, content, out_path}
      end)

'''
render_preflight = render_anchor + '''    # Whole-plan output admission: every rendered file path is checked BEFORE
    # reconciliation bookkeeping or the first filesystem mutation. This avoids
    # partial actuation when a fan-out contains both lawful and forbidden paths.
    if mode == :file do
      Enum.each(renders, fn {_bindings, _content, out_path} ->
        Actuate.admit_output_path!(out_path)
      end)
    end

'''
if render_preflight not in sync:
    if render_anchor not in sync:
        raise SystemExit("sync renders anchor not found")
    sync = sync.replace(render_anchor, render_preflight, 1)

# Remove sanctioned examples of the antipattern from public CLI/docs surfaces.
sync = sync.replace(
    'lib/generated/<%= module_name %>.ex',
    'lib/<%= Macro.underscore(module_name) %>.ex',
)
sync = sync.replace('lib/generated/Multi.Alpha.ex', 'lib/multi/alpha.ex')
sync = sync.replace('lib/generated/Multi.Beta.ex', 'lib/multi/beta.ex')
sync = sync.replace('lib/generated/Multi.Gamma.ex', 'lib/multi/gamma.ex')
sync = sync.replace('lib/generated/resource.ex', 'lib/my_app/resources/resource.ex')
sync = sync.replace('lib/generated.ex', 'lib/my_app/extension.ex')
sync_path.write_text(sync)


# ---------------------------------------------------------------------------
# Reactor: typed whole-plan refusal in :admit. Deletes are deliberately exempt
# so a migration can prune historical generated/ artifacts.
# ---------------------------------------------------------------------------
reactor_path = Path("lib/ggen_igniter/reactors/reconcile_reactor.ex")
reactor = reactor_path.read_text()

admit_docs_old = '''  #   * no admitted item's `canonical_target` may escape the authorized
  #     project root (`GgenIgniter.ArtifactIdentity.within_root?/2`) -- a
'''
admit_docs_new = '''  #   * no admitted `:create`/`:replace`/`:inject` target may resolve through
  #     a directory segment named exactly `generated` -- generated projections
  #     must occupy their canonical source location, never a parallel generated
  #     ownership tree. `:delete` intents are deliberately exempt so stale
  #     historical generated/ artifacts can still be pruned during migration.
  #   * no admitted item's `canonical_target` may escape the authorized
  #     project root (`GgenIgniter.ArtifactIdentity.within_root?/2`) -- a
'''
reactor = replace_once(reactor, admit_docs_old, admit_docs_new, "reactor admit docs")

write_pending_anchor = '''    write_pending = Enum.filter(pending, &(&1.operation in [:create, :replace, :inject]))
    delete_pending = Enum.filter(pending, &(&1.operation == :delete))

'''
write_pending_with_generated = write_pending_anchor + '''    generated_output =
      Enum.find_value(write_pending, fn item ->
        case Actuate.output_path_admission(item.target) do
          {:error, {:refused_generated_directory, canonical_target}} -> canonical_target
          :ok -> nil
        end
      end)

'''
if write_pending_with_generated not in reactor:
    if write_pending_anchor not in reactor:
        raise SystemExit("reactor write_pending anchor not found")
    reactor = reactor.replace(write_pending_anchor, write_pending_with_generated, 1)

cond_anchor = '''    cond do
      duplicates != [] ->
'''
cond_generated = '''    cond do
      generated_output != nil ->
        {:error, {:refused_generated_directory, generated_output}}

      duplicates != [] ->
'''
reactor = replace_once(reactor, cond_anchor, cond_generated, "reactor admission cond")

describe_anchor = '''  defp describe_failure({:refused_path_escapes_root, canonical_target}),
'''
describe_generated = '''  defp describe_failure({:refused_generated_directory, canonical_target}),
    do:
      "refused: output target #{inspect(canonical_target)} resolves through a reserved `generated/` directory"

'''
if describe_generated not in reactor:
    if describe_anchor not in reactor:
        raise SystemExit("reactor describe_failure anchor not found")
    reactor = reactor.replace(describe_anchor, describe_generated + describe_anchor, 1)

plan_docs_old = '''  admission-time refusal (one of `admit_pending/2`'s own tagged reasons:
  `:refused_duplicate_output_path` / `:refused_path_escapes_root` /
  `:refused_unowned_delete` / `:refused_stale_outputs`).
'''
plan_docs_new = '''  admission-time refusal (one of `admit_pending/2`'s own tagged reasons:
  `:refused_generated_directory` / `:refused_duplicate_output_path` /
  `:refused_path_escapes_root` / `:refused_unowned_delete` /
  `:refused_stale_outputs`).
'''
reactor = replace_once(reactor, plan_docs_old, plan_docs_new, "reactor plan refusal docs")
reactor_path.write_text(reactor)


# ---------------------------------------------------------------------------
# README examples: canonical source destinations, never generated/ surfaces.
# ---------------------------------------------------------------------------
readme_path = Path("README.md")
readme = readme_path.read_text()
readme = readme.replace(
    'lib/generated/<%= module_name %>.ex',
    'lib/<%= Macro.underscore(module_name) %>.ex',
)
readme = readme.replace('lib/generated.ex', 'lib/my_app/extension.ex')
readme_path.write_text(readme)


# ---------------------------------------------------------------------------
# Chicago contract: real FS writes/symlink + real Reactor whole-plan refusal.
# ---------------------------------------------------------------------------
test_path = Path("test/generated_directory_policy_test.exs")
test_path.write_text(
    r'''defmodule GgenIgniter.GeneratedDirectoryPolicyTest do
  @moduledoc """
  Chicago-style proof of the reserved `generated/` output invariant: real
  temporary directories, real files, a real filesystem symlink, the real
  `GgenIgniter.Actuate` mutation functions, and a real Reactor admission run.
  No mocks.
  """

  use ExUnit.Case, async: false

  alias GgenIgniter.Actuate
  alias GgenIgniter.Reactors.ReconcileReactor

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
    test "write_new_file!/2 refuses before creating anything", %{root: root} do
      File.cd!(root, fn ->
        path = Path.join(["lib", "generated", "widget.ex"])

        assert_raise ArgumentError, ~r/REFUSED generated_directory/, fn ->
          Actuate.write_new_file!(path, "defmodule Widget, do: :ok\n")
        end

        refute File.exists?(path)
        refute File.exists?(Path.dirname(path))
      end)
    end

    test "write_file!/3 refuses even under dry-run", %{root: root} do
      File.cd!(root, fn ->
        path = Path.join(["lib", "generated", "widget.ex"])

        assert_raise ArgumentError, ~r/REFUSED generated_directory/, fn ->
          Actuate.write_file!(path, "defmodule Widget, do: :ok\n", dry_run: true)
        end

        refute File.exists?(path)
      end)
    end

    test "inject_content!/5 refuses an existing target before mutation", %{root: root} do
      File.cd!(root, fn ->
        path = Path.join(["lib", "generated", "host.ex"])
        File.mkdir_p!(Path.dirname(path))
        original = "defmodule Host do\n  # ggen:slot\nend\n"
        File.write!(path, original)

        assert_raise ArgumentError, ~r/REFUSED generated_directory/, fn ->
          Actuate.inject_content!(path, "# ggen:slot", "  def projected, do: :ok", :after)
        end

        assert File.read!(path) == original
      end)
    end

    test "canonicalization prevents a real symlink alias bypass", %{root: root} do
      generated_dir = Path.join(root, "generated")
      alias_dir = Path.join(root, "projection_alias")
      File.mkdir_p!(generated_dir)
      File.ln_s!(generated_dir, alias_dir)

      File.cd!(root, fn ->
        path = Path.join("projection_alias", "widget.ex")

        assert_raise ArgumentError, ~r/REFUSED generated_directory/, fn ->
          Actuate.write_file!(path, "defmodule Widget, do: :ok\n")
        end
      end)

      refute File.exists?(Path.join(generated_dir, "widget.ex"))
    end

    test "a filename containing generated remains valid", %{root: root} do
      File.cd!(root, fn ->
        path = Path.join("lib", "generated_file.ex")

        assert {:ok, :written} =
                 Actuate.write_file!(path, "defmodule GeneratedFile, do: :ok\n")

        assert File.read!(path) == "defmodule GeneratedFile, do: :ok\n"
      end)
    end
  end

  describe "whole-plan admission" do
    test "Reactor refuses an entire mixed plan before either target is actuated", %{root: root} do
      ontology = Path.join(root, "ontology.ttl")
      query = Path.join(root, "spec.rq")
      template = Path.join(root, "module.ex.eex")
      valid_out = Path.join([root, "lib", "valid.ex"])
      forbidden_out = Path.join([root, "lib", "generated", "forbidden.ex"])

      File.write!(ontology, """
      @prefix ex: <http://example.org/generated-policy#> .
      ex:Subject a ex:Module ; ex:moduleName "GeneratedPolicyFixture" .
      """)

      File.write!(query, """
      PREFIX ex: <http://example.org/generated-policy#>
      SELECT ?module_name WHERE { ex:Subject ex:moduleName ?module_name . }
      """)

      File.write!(template, "defmodule <%= module_name %>, do: nil\n")

      opts = [
        engine: "sparql",
        ontology: ontology,
        manifest_dir: root,
        targets: [
          [query: "spec=#{query}", template: template, out: valid_out],
          [query: "spec=#{query}", template: template, out: forbidden_out]
        ]
      ]

      assert {:error, receipt} = ReconcileReactor.run(opts)
      assert receipt.standing == :refused
      assert receipt.reason =~ "reserved `generated/` directory"
      refute File.exists?(valid_out)
      refute File.exists?(forbidden_out)
    end
  end
end
'''
)
