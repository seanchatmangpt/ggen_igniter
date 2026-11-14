defmodule GgenIgniter.PackFrontmatter.TeraTest do
  use ExUnit.Case, async: true

  alias GgenIgniter.PackFrontmatter.Tera

  test "variables, paths and indexing" do
    env = %{"app" => [%{"name" => "x"}], "n" => 3}
    assert Tera.render("{{ app[0].name }}-{{ n }}", env) == "x-3"
  end

  test "undefined variable in output is a loud error" do
    assert_raise ArgumentError, ~r/not defined/, fn -> Tera.render("{{ nope }}", %{}) end
  end

  test "whitespace control trims newlines on the marked side only" do
    assert Tera.render("a\n{%- if true -%}\n  b\n{%- endif %}\nc", %{}) == "ab\nc"
  end

  test "set + filter(attribute,value) + for + loop.last" do
    env = %{
      "rows" => [%{"k" => "a", "v" => "1"}, %{"k" => "b", "v" => "2"}, %{"k" => "a", "v" => "3"}]
    }

    tpl =
      "{% set mine = rows | filter(attribute=\"k\", value=\"a\") -%}" <>
        "{% for r in mine %}{{ r.v }}{% if not loop.last %},{% endif %}{% endfor %}"

    assert Tera.render(tpl, env) == "1,3"
  end

  test "if / elif / else, == on string-vs-bool, and `| length > 0`" do
    tpl = "{% if x == \"read\" %}R{% elif x == \"destroy\" %}D{% else %}O{% endif %}"
    assert Tera.render(tpl, %{"x" => "read"}) == "R"
    assert Tera.render(tpl, %{"x" => "destroy"}) == "D"
    assert Tera.render(tpl, %{"x" => "create"}) == "O"
    assert Tera.render("{% if l | length > 0 %}y{% endif %}", %{"l" => [1]}) == "y"
    assert Tera.render("{% if l | length > 0 %}y{% endif %}", %{"l" => []}) == ""
    assert Tera.render("{% if p == \"true\" %}T{% endif %}", %{"p" => true}) == "T"
  end

  test "default + split on an undefined optional column" do
    tpl = "{% for t in r.accept | default(value=\"\") | split(pat=\",\") %}[{{ t }}]{% endfor %}"
    assert Tera.render(tpl, %{"r" => %{}}) == "[]"
    assert Tera.render(tpl, %{"r" => %{"accept" => "a,b"}}) == "[a][b]"
  end

  test "undefined optional column is falsy in if" do
    assert Tera.render("{% if s.c %}X{% endif %}", %{"s" => %{}}) == ""
  end

  test "json_encode and comments" do
    assert Tera.render("{# gone #}{{ v | json_encode | safe }}", %{"v" => "a\"b"}) == "\"a\\\"b\""
  end

  test "unsupported constructs raise instead of passing through" do
    assert_raise ArgumentError, ~r/unsupported filter/, fn ->
      Tera.render("{{ v | wat }}", %{"v" => "x"})
    end

    assert_raise ArgumentError, ~r/unsupported or malformed tag/, fn ->
      Tera.render("{% include \"x\" %}", %{})
    end

    assert_raise ArgumentError, ~r/missing/, fn -> Tera.render("{% if true %}x", %{}) end
  end

  test "trailing newline of the template is preserved" do
    assert Tera.render("x\n", %{}) == "x\n"
  end

  describe "macros, set_global, arithmetic, tests, group_by" do
    test "self:: macro with kwargs, whitespace control, elif chain (L07 ref shape)" do
      tpl =
        "{% macro ref(kind, a, b) -%}\n" <>
          "{%- if kind == \"always\" -%}always()\n" <>
          "{%- elif kind == \"action\" -%}action(:{{ a }})\n" <>
          "{%- else -%}{{ kind }}({{ a }})\n" <>
          "{%- endif -%}\n" <>
          "{%- endmacro ref %}\n" <>
          "p {{ self::ref(kind=k, a=x, b=\"\") }} q {{ self::ref(kind=\"always\", a=\"\", b=\"\") }}"

      assert Tera.render(tpl, %{"k" => "action", "x" => "read"}) == "\np action(:read) q always()"
    end

    test "macro is callable before its definition and is isolated from context" do
      tpl = "{{ self::m(a=\"1\") }}{% macro m(a) %}[{{ a }}]{% endmacro m %}"
      assert Tera.render(tpl, %{}) == "[1]"

      iso = "{% macro m(a) %}{{ outer }}{% endmacro m %}{{ self::m(a=1) }}"
      assert_raise ArgumentError, ~r/not defined/, fn -> Tera.render(iso, %{"outer" => "x"}) end
    end

    test "recursive macro with `~` concat and arithmetic argument" do
      tpl =
        "{% macro rec(n, ind) -%}{{ ind }}n={{ n }}" <>
          "{%- if n > 0 %}\n{{ self::rec(n=n - 1, ind=ind ~ \"  \") }}{%- endif %}" <>
          "{%- endmacro rec %}{{ self::rec(n=2, ind=\"\") }}"

      assert Tera.render(tpl, %{}) == "n=2\n  n=1\n    n=0"
    end

    test "unknown macro and non-self namespace stay typed errors" do
      assert_raise ArgumentError, ~r/unknown macro/, fn ->
        Tera.render("{{ self::nope(a=1) }}", %{})
      end

      assert_raise ArgumentError, ~r/unsupported macro namespace/, fn ->
        Tera.render("{{ m::f(a=1) }}", %{})
      end

      assert_raise ArgumentError, ~r/unsupported or malformed tag/, fn ->
        Tera.render("{% macro m(a=1) %}{% endmacro %}", %{})
      end

      assert_raise ArgumentError, ~r/unsupported or malformed tag/, fn ->
        Tera.render("{% import \"x\" as y %}", %{})
      end
    end

    test "set_global survives for-loop scope; plain set does not" do
      tpl =
        "{% set_global first = true %}{% for r in items %}{% if not first %},{% endif %}{{ r }}" <>
          "{% set_global first = false %}{% endfor %}|{{ first }}"

      assert Tera.render(tpl, %{"items" => ["a", "b", "c"]}) == "a,b,c|false"

      local = "{% set v = 1 %}{% for r in items %}{% set v = 2 %}{% endfor %}{{ v }}"
      assert Tera.render(local, %{"items" => ["a"]}) == "1"
    end

    test "arithmetic and concat" do
      assert Tera.render(
               "{{ 1 + 2 * 3 }} {{ 7 - 2 }} {{ 7 % 4 }} {{ n + 10 }} {{ \"a\" ~ 1 ~ \"b\" }}",
               %{"n" => "5"}
             ) ==
               "7 5 3 15 a1b"
    end

    test "tests: defined, starting_with, containing, matching, and `is not`" do
      tpl =
        "{{ \"a:b\" is starting_with(\"a\") }} {{ \"a,b\" is containing(\",\") }} " <>
          "{{ \"ab_1\" is matching(\"^[a-z_][a-z0-9_]*$\") }} {{ \"Ab\" is matching(\"^[a-z]+$\") }} " <>
          "{% if r.flag is defined %}D{% else %}U{% endif %}{% if r.flag is not defined %}N{% endif %}"

      assert Tera.render(tpl, %{"r" => %{"x" => 1}}) == "true true true false UN"

      assert Tera.render("{% if r.flag is defined and r.flag == \"true\" %}Y{% endif %}", %{
               "r" => %{"flag" => "true"}
             }) == "Y"
    end

    test "unsupported test raises typed error" do
      assert_raise ArgumentError, ~r/unsupported test/, fn ->
        Tera.render("{{ 1 is odd }}", %{})
      end
    end

    test "filter(attribute) without value, group_by with two-var for, trim_start_matches" do
      items = [
        %{"name" => "a", "parent" => "p", "ord" => "2"},
        %{"name" => "b", "ord" => "1"},
        %{"name" => "c", "ord" => "2"}
      ]

      assert Tera.render("{{ items | filter(attribute=\"parent\") | length }}", %{
               "items" => items
             }) == "1"

      assert Tera.render(
               "{% for g, xs in items | group_by(attribute=\"ord\") %}{{ g }}:{{ xs | length }};{% endfor %}",
               %{"items" => items}
             ) == "1:1;2:2;"

      assert Tera.render(
               "{% for t in \"?a, b\" | split(pat=\",\") %}[{{ t | trim | trim_start_matches(pat=\"?\") }}]{% endfor %}",
               %{}
             ) == "[a][b]"
    end
  end
end
