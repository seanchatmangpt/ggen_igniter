defmodule GgenIgniter.Render.TeraTest do
  use ExUnit.Case, async: true

  alias GgenIgniter.Render.Tera

  test "plain variable interpolation" do
    assert Tera.render("Hello {{ name }}!", %{"name" => "World"}) == "Hello World!"
  end

  test "dotted field access" do
    template = "Title: {{ d.title }}"
    bindings = %{"d" => %{"title" => "Admitted design"}}
    assert Tera.render(template, bindings) == "Title: Admitted design"
  end

  test "indexed list access followed by field access" do
    template = "{{ rows[0].source }}"
    bindings = %{"rows" => [%{"source" => "fn main() {}"}, %{"source" => "unused"}]}
    assert Tera.render(template, bindings) == "fn main() {}"
  end

  test "for loop over a list" do
    template = "{% for x in items %}[{{ x }}]{% endfor %}"
    assert Tera.render(template, %{"items" => ["a", "b", "c"]}) == "[a][b][c]"
  end

  test "for loop over a list of maps, real ggen-marketplace CMD_REPORT.md.tmpl shape" do
    template = """
    | Order | Dimension | Options |
    |---:|---|---:|
    {% for dimension in dimensions %}| {{ dimension.order }} | `{{ dimension.name }}` | {{ dimension.option_count }} |
    {% endfor %}\
    """

    bindings = %{
      "dimensions" => [
        %{"order" => "1", "name" => "engine", "option_count" => "2"},
        %{"order" => "2", "name" => "mode", "option_count" => "3"}
      ]
    }

    expected = """
    | Order | Dimension | Options |
    |---:|---|---:|
    | 1 | `engine` | 2 |
    | 2 | `mode` | 3 |
    """

    assert Tera.render(template, bindings) == expected
  end

  test "if/endif with true condition, no else" do
    assert Tera.render("{% if flag %}yes{% endif %}", %{"flag" => true}) == "yes"
  end

  test "if/endif with false condition, no else, renders nothing" do
    assert Tera.render("{% if flag %}yes{% endif %}", %{"flag" => false}) == ""
  end

  test "if/else/endif picks the else branch on falsy/missing value" do
    template = "{% if candidate.authority %}{{ candidate.authority }}{% else %}none{% endif %}"
    assert Tera.render(template, %{"candidate" => %{"authority" => nil}}) == "none"
    assert Tera.render(template, %{"candidate" => %{"authority" => "alice"}}) == "alice"
  end

  test "comments are stripped entirely" do
    template = "before{# this whole comment vanishes #}after"
    assert Tera.render(template, %{}) == "beforeafter"
  end

  test "capitalize filter" do
    assert Tera.render("{{ name | capitalize }}", %{"name" => "world"}) == "World"
  end

  test "capitalize filter on already-capitalized and empty string" do
    assert Tera.render("{{ name | capitalize }}", %{"name" => "World"}) == "World"
    assert Tera.render("{{ name | capitalize }}", %{"name" => ""}) == ""
  end

  test "filter(attribute=,value=) selects matching list items" do
    template =
      "{% for c in candidates | filter(attribute=\"standing\", value=\"authorized\") %}{{ c.name }},{% endfor %}"

    bindings = %{
      "candidates" => [
        %{"name" => "alpha", "standing" => "authorized"},
        %{"name" => "beta", "standing" => "candidate"},
        %{"name" => "gamma", "standing" => "authorized"}
      ]
    }

    assert Tera.render(template, bindings) == "alpha,gamma,"
  end

  test "full real-shaped template: CMD_REPORT.md.tmpl candidate table with for + if/else + filters" do
    template = """
    # CMD verifier report

    {% for d in design %}## Admitted design

    - **Title:** {{ d.title }}
    - **Coverage:** `{{ d.coverage }}`
    {% endfor %}
    | Candidate | Standing | Authority |
    |---|---|---|
    {% for candidate in candidates %}| `{{ candidate.name }}` | `{{ candidate.standing }}` | `{% if candidate.authority %}{{ candidate.authority }}{% else %}none{% endif %}` |
    {% endfor %}\
    """

    bindings = %{
      "design" => [%{"title" => "CMD Verifier", "coverage" => "full"}],
      "candidates" => [
        %{"name" => "cand-a", "standing" => "authorized", "authority" => "reviewer-1"},
        %{"name" => "cand-b", "standing" => "candidate", "authority" => nil}
      ]
    }

    expected = """
    # CMD verifier report

    ## Admitted design

    - **Title:** CMD Verifier
    - **Coverage:** `full`

    | Candidate | Standing | Authority |
    |---|---|---|
    | `cand-a` | `authorized` | `reviewer-1` |
    | `cand-b` | `candidate` | `none` |
    """

    assert Tera.render(template, bindings) == expected
  end

  test "existing EEx renderer (GgenIgniter.Render) still works unmodified alongside the new Tera engine" do
    assert GgenIgniter.Render.render("Hello <%= name %>!", name: "World") == "Hello World!"
  end
end
