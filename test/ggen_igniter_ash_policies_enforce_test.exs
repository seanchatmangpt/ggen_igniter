defmodule GgenIgniter.AshPoliciesEnforceTest do
  @moduledoc """
  Chicago-style: renders `priv/ggen/ash-igniter-api-pack` (real `mix ggen_igniter.sync`
  subprocess) from an ontology carrying `aia:PolicyRule` / `aia:PolicyCheck` (bypass, policy with
  forbid_if + authorize_if combos, multiple checks) and `aia:FieldPolicy` / `aia:FieldCheck`, runs
  the rendered task against a real `Igniter.Test.test_project/1`, compiles the resulting resource
  with the real compiler and ENFORCES it with real `Ash.can?/2` and `Ash.create/3` calls carrying
  actors on the ETS data layer. Unprivileged actors are denied (`%Ash.Error.Forbidden{}`, stored
  rows unchanged), privileged actors succeed, a field policy yields `%Ash.ForbiddenField{}`.

  Falsifier: swapping `forbid_if` for `authorize_if` in the ontology flips the banned actor from
  denied to allowed. Idempotence: a second run of the policy-bearing task changes nothing.
  Malformed policy facts are refused (typed `REFUSED_ASH_API_SURFACE`, non-zero exit, no file).
  No doubles, no mocks.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  import Igniter.Test

  alias GgenIgniter.Test.PackCompile

  @moduletag :integration
  @moduletag timeout: 1_800_000

  @domain Vault.Docs
  @document Vault.Docs.Doc
  @task Mix.Tasks.Vault.Manufacture.Docs

  @ontology """
  @prefix aia: <https://ggen-igniter.dev/ontology/ash-igniter-api#> .
  aia:project a aia:Project ; aia:otpApp "vault" ;
      aia:taskModule "Mix.Tasks.Vault.Manufacture.Docs" ; aia:taskName "vault.manufacture.docs" .
  aia:resDoc a aia:Resource ; aia:resourceModule "Vault.Docs.Doc" ; aia:domainModule "Vault.Docs" ; aia:order 1 .

  aia:extEts a aia:Extension ; aia:resourceOf aia:resDoc ; aia:extensionName "ets" ; aia:order 1 .
  aia:extPolicy a aia:Extension ; aia:resourceOf aia:resDoc ; aia:extensionName "Ash.Policy.Authorizer" ; aia:order 2 .

  aia:attrTitle a aia:Attribute ; aia:resourceOf aia:resDoc ; aia:attributeName "title" ;
      aia:attributeType "string" ; aia:isPublic true ; aia:isRequired true ; aia:order 1 .
  aia:attrSecret a aia:Attribute ; aia:resourceOf aia:resDoc ; aia:attributeName "secret" ;
      aia:attributeType "string" ; aia:isPublic true ; aia:isRequired false ; aia:order 2 .

  aia:actRead a aia:Action ; aia:resourceOf aia:resDoc ; aia:actionName "read" ;
      aia:actionType "read" ; aia:accepts "" ; aia:order 1 .
  aia:primRead a aia:PrimaryAction ; aia:actionOf aia:actRead .
  aia:actWrite a aia:Action ; aia:resourceOf aia:resDoc ; aia:actionName "write" ;
      aia:actionType "create" ; aia:accepts "title,secret" ; aia:order 2 .
  aia:actEdit a aia:Action ; aia:resourceOf aia:resDoc ; aia:actionName "edit" ;
      aia:actionType "update" ; aia:accepts "title" ; aia:order 3 .

  # bypass: a superuser passes every policy
  aia:ruleSuper a aia:PolicyRule ; aia:resourceOf aia:resDoc ; aia:ruleKind "bypass" ;
      aia:ruleCondition "actor_attribute_equals(:role, :superuser)" ; aia:order 1 .
  aia:chkSuper a aia:PolicyCheck ; aia:checkOf aia:ruleSuper ; aia:checkKind "authorize_if" ;
      aia:checkExpr "always()" ; aia:order 1 .

  aia:ruleRead a aia:PolicyRule ; aia:resourceOf aia:resDoc ; aia:ruleKind "policy" ;
      aia:ruleCondition "action_type(:read)" ; aia:order 2 .
  aia:chkRead a aia:PolicyCheck ; aia:checkOf aia:ruleRead ; aia:checkKind "authorize_if" ;
      aia:checkExpr "always()" ; aia:order 1 .

  # combo on create: banned actors are forbidden BEFORE the editor authorization is consulted
  aia:ruleCreate a aia:PolicyRule ; aia:resourceOf aia:resDoc ; aia:ruleKind "policy" ;
      aia:ruleCondition "action_type(:create)" ; aia:order 3 .
  aia:chkBanned a aia:PolicyCheck ; aia:checkOf aia:ruleCreate ; aia:checkKind "forbid_if" ;
      aia:checkExpr "actor_attribute_equals(:role, :banned)" ; aia:order 1 .
  aia:chkEditor a aia:PolicyCheck ; aia:checkOf aia:ruleCreate ; aia:checkKind "authorize_if" ;
      aia:checkExpr "actor_attribute_equals(:role, :editor)" ; aia:order 2 .
  aia:chkAdmin a aia:PolicyCheck ; aia:checkOf aia:ruleCreate ; aia:checkKind "authorize_if" ;
      aia:checkExpr "actor_attribute_equals(:role, :admin)" ; aia:order 3 .

  aia:ruleUpdate a aia:PolicyRule ; aia:resourceOf aia:resDoc ; aia:ruleKind "policy" ;
      aia:ruleCondition "action_type(:update)" ; aia:order 4 .
  aia:chkUpdate a aia:PolicyCheck ; aia:checkOf aia:ruleUpdate ; aia:checkKind "authorize_if" ;
      aia:checkExpr "actor_attribute_equals(:role, :editor)" ; aia:order 1 .

  # field policies: `secret` is admin-only, everything else visible
  aia:fpSecret a aia:FieldPolicy ; aia:resourceOf aia:resDoc ; aia:fieldNames "secret" ; aia:order 1 .
  aia:fcSecret a aia:FieldCheck ; aia:fieldPolicyOf aia:fpSecret ; aia:checkKind "authorize_if" ;
      aia:checkExpr "actor_attribute_equals(:role, :admin)" ; aia:order 1 .
  aia:fpRest a aia:FieldPolicy ; aia:resourceOf aia:resDoc ; aia:fieldNames "*" ; aia:order 2 .
  aia:fcRest a aia:FieldCheck ; aia:fieldPolicyOf aia:fpRest ; aia:checkKind "authorize_if" ;
      aia:checkExpr "always()" ; aia:order 1 .
  """

  # Ash.Policy.Authorizer needs a SAT solver, detected by `crux` at ITS compile time. This
  # project declares none, so the solver is provided here from real source: compile simple_sat
  # (pure Elixir) with the real compiler, then recompile the REAL crux implementation module so
  # it binds the loaded solver -- the same effect as `mix deps.compile crux --force` with the
  # dependency present. Skipped, visibly, when no simple_sat source exists on this machine.
  @sat_source Enum.find(
                [
                  Path.expand("deps/simple_sat/lib/simple_sat.ex"),
                  Path.expand("~/ash_a2a/deps/simple_sat/lib/simple_sat.ex"),
                  Path.expand("~/ash_r2rml/deps/simple_sat/lib/simple_sat.ex")
                ],
                &File.exists?/1
              )
  @crux_impl Path.expand("deps/crux/lib/crux/implementation.ex")
  @sat_skip if(@sat_source == nil,
              do: "no simple_sat source on this machine (needed by Ash.Policy.Authorizer)",
              else: false
            )

  setup_all do
    if @sat_skip do
      :ok
    else
      restore = ensure_sat_solver!()
      on_exit(restore)
    end

    :ok
  end

  setup do
    on_exit(fn -> safe_stop(@document) end)
    :ok
  end

  describe "enforcement with actors" do
    @describetag skip: @sat_skip

    test "unprivileged denied, privileged allowed, bypass passes, state unchanged on denial" do
      with_built(@ontology, fn built ->
        guest = %{role: :guest}
        editor = %{role: :editor}
        admin = %{role: :admin}
        banned = %{role: :banned}
        superuser = %{role: :superuser}

        refute Ash.can?({@document, :write}, guest)
        assert Ash.can?({@document, :write}, editor)
        assert Ash.can?({@document, :write}, admin)
        # forbid_if wins over a later authorize_if for the same actor
        refute Ash.can?({@document, :write}, banned)
        assert Ash.can?({@document, :write}, superuser)

        assert {:error, %Ash.Error.Forbidden{}} =
                 Ash.create(@document, %{title: "no"}, action: :write, actor: guest)

        assert [] == Ash.read!(@document, authorize?: false)

        doc = Ash.create!(@document, %{title: "yes", secret: "s3"}, action: :write, actor: editor)
        assert [%{title: "yes"}] = Ash.read!(@document, authorize?: false)

        # update: only editors; the superuser passes through the bypass
        refute Ash.can?({doc, :edit}, guest)
        assert Ash.can?({doc, :edit}, editor)
        assert Ash.can?({doc, :edit}, superuser)

        assert {:error, %Ash.Error.Forbidden{}} =
                 doc
                 |> Ash.Changeset.for_update(:edit, %{title: "hax"}, actor: guest)
                 |> Ash.update()

        assert Ash.read!(@document, authorize?: false) |> hd() |> Map.get(:title) == "yes"

        src = built.sources[@document]
        assert src =~ "bypass(actor_attribute_equals(:role, :superuser))"
        assert src =~ "forbid_if(actor_attribute_equals(:role, :banned))"
      end)
    end

    test "field policy hides the secret from a non-admin as %Ash.ForbiddenField{}" do
      with_built(@ontology, fn _built ->
        Ash.create!(@document, %{title: "t", secret: "s3"},
          action: :write,
          actor: %{role: :superuser}
        )

        [as_editor] = Ash.read!(@document, actor: %{role: :editor})
        assert %Ash.ForbiddenField{field: :secret} = as_editor.secret
        assert as_editor.title == "t"

        [as_admin] = Ash.read!(@document, actor: %{role: :admin})
        assert as_admin.secret == "s3"
      end)
    end

    test "FALSIFIER: swapping forbid_if for authorize_if flips the banned actor to allowed" do
      variant =
        String.replace(
          @ontology,
          ~s|aia:chkBanned a aia:PolicyCheck ; aia:checkOf aia:ruleCreate ; aia:checkKind "forbid_if"|,
          ~s|aia:chkBanned a aia:PolicyCheck ; aia:checkOf aia:ruleCreate ; aia:checkKind "authorize_if"|
        )

      refute variant == @ontology

      with_built(variant, fn _built ->
        assert Ash.can?({@document, :write}, %{role: :banned})
      end)
    end

    test "idempotent: a second run of the policy-bearing task changes nothing" do
      task = render_and_compile!(@ontology)

      try do
        applied = test_project(app_name: :vault) |> run() |> apply_igniter!()
        second = run(applied)
        assert_unchanged(second)
        assert second.issues == []
        assert second.warnings == [], "warnings: #{inspect(second.warnings)}"
        path = Igniter.Project.Module.proper_location(applied, @document)
        src = content(applied, path)
        assert length(Regex.scan(~r/bypass\(/, src)) == 1
        assert length(Regex.scan(~r/field_policy[ (]/, src)) == 2
      after
        purge(task)
      end
    end
  end

  describe "NEGATIVE: malformed policy facts are refused (typed, non-zero, nothing written)" do
    test "unknown check kind" do
      bad =
        String.replace(@ontology, ~s|aia:checkKind "forbid_if"|, ~s|aia:checkKind "permit_if"|)

      assert {output, code, false} = sync_refused(bad)
      assert code != 0
      assert output =~ "REFUSED_ASH_API_SURFACE"
      assert output =~ "UNKNOWN_CHECK_KIND"
    end

    test "a rule with no checks and a check on a missing rule" do
      bad =
        @ontology <>
          """
          aia:ruleEmpty a aia:PolicyRule ; aia:resourceOf aia:resDoc ; aia:ruleKind "policy" ;
              aia:ruleCondition "action_type(:destroy)" ; aia:order 9 .
          aia:chkOrphan a aia:PolicyCheck ; aia:checkOf aia:noSuchRule ; aia:checkKind "authorize_if" ;
              aia:checkExpr "always()" ; aia:order 1 .
          """

      assert {output, code, false} = sync_refused(bad)
      assert code != 0
      assert output =~ "POLICY_RULE_WITHOUT_CHECKS"
      assert output =~ "DANGLING_POLICY_RULE"
    end

    test "a field policy with no checks" do
      bad =
        @ontology <>
          """
          aia:fpEmpty a aia:FieldPolicy ; aia:resourceOf aia:resDoc ; aia:fieldNames "title" ; aia:order 9 .
          """

      assert {output, code, false} = sync_refused(bad)
      assert code != 0
      assert output =~ "FIELD_POLICY_WITHOUT_CHECKS"
    end
  end

  # ------------------------------------------------------------------ helpers

  # Renders + compiles the task, applies it to a fresh test project, compiles the resulting
  # domain/resource sources, runs `fun`, always purges.
  defp with_built(ontology, fun) do
    task_modules = render_and_compile!(ontology)

    try do
      igniter = test_project(app_name: :vault) |> run() |> apply_igniter!()

      sources =
        for m <- [@domain, @document], into: %{} do
          {m, content(igniter, Igniter.Project.Module.proper_location(igniter, m))}
        end

      dir =
        PackCompile.tmp_project!(
          for {m, src} <- sources, into: %{}, do: {"#{inspect(m)}.ex", src}
        )

      try do
        modules = PackCompile.compile!(dir)

        try do
          fun.(%{sources: sources, igniter: igniter})
        after
          for m <- [@document], do: safe_stop(m)
          purge(modules)
        end
      after
        PackCompile.cleanup(dir)
      end
    after
      purge(task_modules)
    end
  end

  defp ensure_sat_solver! do
    try do
      Crux.Implementation.check!()
      fn -> :ok end
    rescue
      _ ->
        sat_modules = PackCompile.compile!([@sat_source])
        recompile_crux!()

        fn ->
          purge(sat_modules)
          recompile_crux!()
        end
    end
  end

  defp recompile_crux! do
    previous = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      Code.compile_file(@crux_impl)
    after
      Code.put_compiler_option(:ignore_module_conflict, previous)
    end
  end

  # PackCompile.purge/1 calls Code.del_path/1, which does not exist on this Elixir (it is
  # Code.delete_path/1); unload and drop the tmp ebin with the real API here.
  defp purge(modules) do
    ebins =
      for m <- modules,
          path = :code.which(m),
          is_list(path),
          dir = path |> List.to_string() |> Path.dirname(),
          String.contains?(dir, "pack_compile_ebin_"),
          uniq: true,
          do: dir

    for m <- modules do
      :code.purge(m)
      :code.delete(m)
      :code.purge(m)
    end

    for dir <- ebins do
      Code.delete_path(dir)
      File.rm_rf!(dir)
    end

    :ok
  end

  defp safe_stop(m) do
    Ash.DataLayer.Ets.stop(m)
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp render_and_compile!(ontology) do
    dir = PackCompile.tmp_project!(%{"ontology.ttl" => ontology})
    on_exit(fn -> PackCompile.cleanup(dir) end)
    # ASH_API_PACK_DIR points at another pack tree (e.g. the pre-change pack extracted with
    # `git show`) to witness these tests RED against it; unset = the shipped pack.
    pack_opts =
      case System.get_env("ASH_API_PACK_DIR") do
        nil -> []
        pack_dir -> [pack_dir: pack_dir]
      end

    rendered =
      PackCompile.render!(
        "ash-igniter-api-pack",
        [ontology: Path.join(dir, "ontology.ttl")] ++ pack_opts
      )

    on_exit(fn -> PackCompile.cleanup(rendered.out_dir) end)
    PackCompile.compile!(Enum.filter(rendered.files, &String.ends_with?(&1, ".ex")))
  end

  # Real sync subprocess expected to REFUSE: returns {output, exit_code, out_file_exists?}.
  defp sync_refused(ontology) do
    dir = PackCompile.tmp_project!(%{"ontology.ttl" => ontology})
    on_exit(fn -> PackCompile.cleanup(dir) end)
    out = Path.join(dir, "lib/task.ex")

    {output, code} =
      System.cmd(
        "mix",
        [
          "ggen_igniter.sync",
          "--pack",
          "ash-igniter-api-pack",
          "--engine",
          "sparql",
          "--ontology",
          Path.join(dir, "ontology.ttl"),
          "--out",
          out,
          "--manifest-dir",
          dir,
          "--verify-cwd",
          File.cwd!()
        ],
        cd: File.cwd!(),
        stderr_to_stdout: true
      )

    {output, code, File.exists?(out)}
  end

  defp run(igniter) do
    parent = self()

    capture_io(:stderr, fn ->
      capture_io(fn -> send(parent, {:igniter, Igniter.compose_task(igniter, @task, [])}) end)
    end)

    receive do
      {:igniter, result} -> result
    after
      5_000 -> raise "timed out waiting for compose_task"
    end
  end

  defp content(igniter, path) do
    igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)
  end
end
