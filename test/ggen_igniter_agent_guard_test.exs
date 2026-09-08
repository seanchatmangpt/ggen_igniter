defmodule GgenIgniterAgentGuardTest do
  @moduledoc """
  Real-subprocess coverage for the two `PreToolUse` guards in `.claude/`.

  Before this file the hand-write guard was exercised only by four cases inside
  `test/fixtures/ash_manufacture_pack/bin/qualify.sh`, all of them `tool_name`
  `Write` with a `content` key, and only during a full qualification run. That
  is one payload shape out of the several the hook actually receives, so four
  measured bypasses survived a green qualification.

  Every case here runs the real hook as a real subprocess over the real stdin
  JSON protocol and asserts the real exit status. No doubles: a guard whose
  standing comes from a stand-in is exactly the failure its own header records.
  """
  use ExUnit.Case, async: true

  # ---------------------------------------------------------------- contracts
  # Upstream CONTRACT (Claude Code PreToolUse protocol), not test data: the
  # hook runner delivers the tool call as JSON on stdin under exactly these
  # keys. Faker must not generate them -- a generated key would test nothing.
  @k_tool_name "tool_name"
  @k_tool_input "tool_input"
  @k_file_path "file_path"
  @k_notebook_path "notebook_path"
  @k_content "content"
  @k_new_string "new_string"
  @k_old_string "old_string"
  @k_new_source "new_source"
  @k_edits "edits"
  @k_command "command"

  # Upstream CONTRACT: hook exit codes. 2 blocks the tool call and shows
  # stderr to the agent; 0 allows it. Any other status is neither.
  @blocked 2
  @allowed 0

  # Upstream CONTRACT: the Ash declarations whose hand-authoring is refused,
  # and the destructive shell command the sibling guard refuses. These are
  # fixed tokens in someone else's vocabulary, not values we are free to vary.
  @ash_resource "Ash.Resource"
  @ash_domain "Ash.Domain"
  @rm_rf "rm -rf"

  # ------------------------------------------------------------------- paths
  defp repo_root, do: Path.expand("..", __DIR__)
  defp guard_script, do: Path.join(repo_root(), ".claude/hooks/refuse-handwritten-ash.sh")
  defp settings_json, do: Path.join(repo_root(), ".claude/settings.json")

  # ------------------------------------------------------------------ runners
  defp tmp_write(contents, ext) do
    file =
      Path.join(
        System.tmp_dir!(),
        "ggen-guard-#{System.unique_integer([:positive, :monotonic])}#{ext}"
      )

    File.write!(file, contents)
    on_exit(fn -> File.rm(file) end)
    file
  end

  # `System.cmd/3` cannot write to a child's stdin, so the payload goes to a
  # file and `sh -c` pipes it in. That keeps the hook's own view identical to
  # production: JSON arriving on a pipe, stdin not a tty.
  defp run_guard_raw(raw_payload) do
    json = tmp_write(raw_payload, ".json")

    {_out, status} =
      System.cmd("sh", ["-c", "cat '#{json}' | bash '#{guard_script()}'"], stderr_to_stdout: true)

    status
  end

  defp run_guard(payload) when is_map(payload), do: run_guard_raw(Jason.encode!(payload))

  # The destructive-command guard lives inline in settings.json rather than in
  # its own script, so the test reads the exact string the hook runner would
  # run. Reading it here (rather than restating it) means an edit that
  # reintroduces the env-only read fails this test instead of passing it.
  defp bash_hook_command do
    settings_json()
    |> File.read!()
    |> Jason.decode!()
    |> get_in(["hooks", "PreToolUse"])
    |> Enum.find(&(&1["matcher"] == "Bash"))
    |> get_in(["hooks", Access.at(0), "command"])
  end

  defp run_bash_guard(payload) do
    json = tmp_write(Jason.encode!(payload), ".json")
    script = tmp_write(bash_hook_command(), ".sh")

    # CLAUDE_TOOL_INPUT is deliberately unset: the whole defect is that the
    # guard read only that variable, which the real runner never sets.
    {_out, status} =
      System.cmd("sh", ["-c", "cat '#{json}' | bash '#{script}'"],
        stderr_to_stdout: true,
        env: [{"CLAUDE_TOOL_INPUT", nil}]
      )

    status
  end

  # --------------------------------------------------------------- faker data
  defp camel_word do
    Faker.Lorem.word()
    |> String.replace(~r/[^A-Za-z]/, "")
    |> String.capitalize()
    |> case do
      "" -> "Zed"
      w -> w
    end
  end

  defp snake_word do
    Faker.Lorem.word()
    |> String.replace(~r/[^a-z]/, "")
    |> case do
      "" -> "zed"
      w -> w
    end
  end

  defp app_name, do: snake_word()
  defp module_name, do: "#{camel_word()}.#{camel_word()}"

  defp lib_path(app \\ nil, stem \\ nil),
    do: "/#{snake_word()}/lib/#{app || app_name()}/#{stem || snake_word()}.ex"

  # A hand-authored resource header, with the module and domain names varying
  # per run so the detector cannot be passing on a memorised fixture string.
  defp resource_source(decl \\ nil) do
    """
    defmodule #{module_name()} do
      #{decl || "use #{@ash_resource}, domain: #{module_name()}"}

      attributes do
        attribute :#{snake_word()}, :string
      end
    end
    """
  end

  # =========================================================== 1. transport
  describe "hand-write guard / transport" do
    test "blocks a resource carried under edits[].new_string (MultiEdit shape)" do
      payload = %{
        @k_tool_name => "MultiEdit",
        @k_tool_input => %{
          @k_file_path => lib_path(),
          @k_edits => [%{@k_old_string => "", @k_new_string => resource_source()}]
        }
      }

      assert run_guard(payload) == @blocked
    end

    test "blocks a resource carried under an unrecognised body key" do
      payload = %{
        @k_tool_name => "Write",
        @k_tool_input => %{
          @k_file_path => lib_path(),
          # Not one of the four keys the original parser knew about.
          "source_text" => resource_source()
        }
      }

      assert run_guard(payload) == @blocked
    end

    test "blocks a resource carried under notebook_path/new_source" do
      payload = %{
        @k_tool_name => "NotebookEdit",
        @k_tool_input => %{
          @k_notebook_path => lib_path(),
          @k_new_source => resource_source()
        }
      }

      assert run_guard(payload) == @blocked
    end

    test "blocks a resource nested two levels below tool_input" do
      payload = %{
        @k_tool_name => "Edit",
        @k_tool_input => %{
          @k_file_path => lib_path(),
          "batch" => %{"changes" => [%{@k_new_string => resource_source()}]}
        }
      }

      assert run_guard(payload) == @blocked
    end
  end

  # ============================================================== 2. detector
  describe "hand-write guard / detector" do
    test "blocks the parenthesised macro call use(Ash.Resource, ...)" do
      decl = "use(#{@ash_resource}, domain: #{module_name()})"
      payload = write_payload(lib_path(), resource_source(decl))
      assert run_guard(payload) == @blocked
    end

    test "blocks an alias continuation split across a newline" do
      decl = "use #{String.replace(@ash_resource, ".", ".\n    ")}"
      payload = write_payload(lib_path(), resource_source(decl))
      assert run_guard(payload) == @blocked
    end

    test "blocks use Ash.Domain in every spacing the compiler accepts" do
      for decl <- ["use #{@ash_domain}", "use(#{@ash_domain})", "use  #{@ash_domain}"] do
        payload = write_payload(lib_path(), resource_source(decl))
        assert run_guard(payload) == @blocked, "expected #{inspect(decl)} to be refused"
      end
    end

    test "blocks a base-resource header (otp_app: + domain: pair)" do
      body = "use #{module_name()}, otp_app: :#{app_name()}, domain: #{module_name()}"
      assert run_guard(write_payload(lib_path(), body)) == @blocked
    end
  end

  # ================================================================== 3. path
  describe "hand-write guard / path normalisation" do
    test "blocks a lib/ resource reached through the mix-tasks allowlist" do
      app = app_name()
      path = "/#{snake_word()}/lib/mix/tasks/../#{app}/#{snake_word()}.ex"
      assert run_guard(write_payload(path, resource_source())) == @blocked
    end

    test "blocks a lib/ resource reached through the deps allowlist" do
      path = "/#{snake_word()}/deps/../lib/#{app_name()}/#{snake_word()}.ex"
      assert run_guard(write_payload(path, resource_source())) == @blocked
    end

    test "blocks a resource in an unanchored directory merely named templates" do
      path = "/#{snake_word()}/lib/#{app_name()}/templates/#{snake_word()}.ex"
      assert run_guard(write_payload(path, resource_source())) == @blocked
    end

    test "blocks a resource whose path still contains .. after normalisation" do
      path = "../#{snake_word()}/lib/#{app_name()}/templates/#{snake_word()}.ex"
      assert run_guard(write_payload(path, resource_source())) == @blocked
    end
  end

  # ============================================================== 4. allowing
  # Over-blocking is a real failure too: a guard that refuses ordinary work
  # gets disabled, and a disabled guard refuses nothing.
  describe "hand-write guard / allowed" do
    test "allows ordinary Elixir" do
      body = """
      defmodule #{module_name()} do
        def #{snake_word()}, do: :#{snake_word()}
      end
      """

      assert run_guard(write_payload(lib_path(), body)) == @allowed
    end

    test "allows the composed manufacture task, which COMPOSES the generators" do
      app = app_name()
      path = "/#{snake_word()}/lib/mix/tasks/#{app}.manufacture.ex"

      body = """
      defmodule Mix.Tasks.#{camel_word()}.Manufacture do
        use Igniter.Mix.Task

        def igniter(igniter) do
          Igniter.compose_task(igniter, "ash.gen.resource", ["#{module_name()}"])
        end
      end
      """

      assert run_guard(write_payload(path, body)) == @allowed
    end

    test "allows an Edit that only DELETES a resource header" do
      payload = %{
        @k_tool_name => "Edit",
        @k_tool_input => %{
          @k_file_path => lib_path(),
          @k_old_string => resource_source(),
          @k_new_string => ""
        }
      }

      assert run_guard(payload) == @allowed
    end

    test "allows an empty payload" do
      assert run_guard_raw("") == @allowed
    end

    test "allows a pack template, whose job is to MODEL the construct" do
      path = "/#{snake_word()}/priv/ggen/#{snake_word()}-pack/templates/#{snake_word()}.ex"
      assert run_guard(write_payload(path, resource_source())) == @allowed
    end

    test "allows the ash-lifecycle-pack fixture tree" do
      path = "/#{snake_word()}/test/fixtures/ash-lifecycle-pack/#{snake_word()}.ex"
      assert run_guard(write_payload(path, resource_source())) == @allowed
    end

    test "allows a non-Elixir extension: the extension gate owns it, not the allowlist" do
      # This is the observable reason the *.eex / *.ttl / *.rq / *.md allowlist
      # rows were dead: control never reaches them.
      path = "/#{snake_word()}/lib/#{app_name()}/#{snake_word()}.ex.eex"
      assert run_guard(write_payload(path, resource_source())) == @allowed
    end
  end

  # ============================================================ 5. fail-closed
  describe "hand-write guard / unparseable payload" do
    test "does not fail open on a payload that is not JSON" do
      assert run_guard_raw("this is not json " <> resource_source()) == @blocked
    end

    test "does not fail open when the body sits outside tool_input" do
      raw = Jason.encode!(%{@k_tool_name => "Write", @k_content => resource_source()})
      assert run_guard_raw(raw) == @blocked
    end
  end

  # ====================================================== 6. sibling guard
  describe "destructive-command guard" do
    test "blocks rm -rf delivered on stdin with no CLAUDE_TOOL_INPUT set" do
      payload = %{
        @k_tool_name => "Bash",
        @k_tool_input => %{@k_command => "#{@rm_rf} #{repo_root()}/lib"}
      }

      assert run_bash_guard(payload) == @blocked
    end

    test "blocks git reset --hard delivered on stdin" do
      payload = %{
        @k_tool_name => "Bash",
        @k_tool_input => %{@k_command => "git reset --hard origin/#{snake_word()}"}
      }

      assert run_bash_guard(payload) == @blocked
    end

    test "blocks git push --force delivered on stdin" do
      payload = %{
        @k_tool_name => "Bash",
        @k_tool_input => %{@k_command => "git push origin #{snake_word()} --force"}
      }

      assert run_bash_guard(payload) == @blocked
    end

    test "allows an ordinary command" do
      payload = %{
        @k_tool_name => "Bash",
        @k_tool_input => %{@k_command => "grep -rn #{snake_word()} lib/"}
      }

      assert run_bash_guard(payload) == @allowed
    end
  end

  # ------------------------------------------------------------------ helper
  defp write_payload(path, body) do
    %{
      @k_tool_name => "Write",
      @k_tool_input => %{@k_file_path => path, @k_content => body}
    }
  end
end
