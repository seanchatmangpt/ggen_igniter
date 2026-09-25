# Origin-authority court run (AC-03/F-02). Real SHACL + Authority.index/resolve over the canonical ontology.
alias GgenIgniter.Ontology
alias GgenIgniter.SemanticJira.{Authority, Shacl}
sj = "https://ggen-igniter.dev/ontology/semantic-jira#"
onto_path = "priv/ggen/semantic-jira-pack/ontology.ttl"
shapes_path = "priv/ggen/semantic-jira-pack/shapes/work-order.shacl.ttl"
graph = Ontology.load!(onto_path)
shapes = Ontology.load!(shapes_path)
report = Shacl.validate(graph, shapes)
index = Authority.index(graph)
wo = RDF.iri(sj <> "WorkOrder")
orders =
  graph |> RDF.Graph.descriptions()
  |> Enum.filter(fn d -> wo in RDF.Description.get(d, RDF.type(), []) end)
rows =
  Enum.map(orders, fn d ->
    origins = RDF.Description.get(d, RDF.iri(sj <> "originAuthority"), []) |> Enum.map(&to_string/1) |> Enum.sort()
    verdict =
      case origins do
        [o] -> case Authority.resolve(index, o) do
                 {:ok, dig} -> %{admitted: true, digest: dig}
                 {:error, r} -> %{admitted: false, refusal: inspect(r)}
               end
        [] -> %{admitted: false, refusal: "origin_authority_missing"}
        many -> %{admitted: false, refusal: "ambiguous_origin_authority:" <> Enum.join(many, ",")}
      end
    Map.merge(%{order: to_string(d.subject), origins: origins}, verdict)
  end) |> Enum.sort_by(& &1.order)
counts = rows |> Enum.filter(& &1.admitted) |> Enum.frequencies_by(fn r -> hd(r.origins) end)
unadmitted = Enum.reject(rows, & &1.admitted)
# Falsifier probes (F-02): zero and multiple origins must be refused by the real SHACL court + index.
first = hd(orders).subject
zero = RDF.Graph.delete(graph, {first, RDF.iri(sj <> "originAuthority"), RDF.Graph.get(graph, first) |> RDF.Description.first(RDF.iri(sj <> "originAuthority"))})
two = RDF.Graph.add(graph, {first, RDF.iri(sj <> "originAuthority"), RDF.iri(sj <> "objective-semantic-jira-mvp")})
two = if length(RDF.Description.get(RDF.Graph.get(two, first), RDF.iri(sj <> "originAuthority"))) < 2,
  do: RDF.Graph.add(graph, {first, RDF.iri(sj <> "originAuthority"), RDF.iri(sj <> "objective-project-manufacturer")}), else: two
zr = Shacl.validate(zero, shapes)
tr = Shacl.validate(two, shapes)
zv = Authority.verify_origin(zero, graph, to_string(first))
tv = Authority.verify_origin(two, graph, to_string(first))
out = %{
  shacl_conforms: report.conforms, shacl_violations: length(report.violations),
  shacl_focus_nodes: report.focus_node_count,
  authority_admitted: index.admitted |> Map.keys() |> Enum.sort(),
  authority_refused: index.refused |> Enum.map(fn {k, v} -> "#{k}=#{inspect(v)}" end) |> Enum.sort(),
  orders_total: length(rows), orders_admitted: length(rows) - length(unadmitted),
  unadmitted: unadmitted, origin_counts: counts,
  falsifiers: %{
    zero_origin: %{order: to_string(first), shacl_conforms: zr.conforms, shacl_violations: length(zr.violations), verify_origin: inspect(zv)},
    multiple_origin: %{order: to_string(first), shacl_conforms: tr.conforms, shacl_violations: length(tr.violations), verify_origin: inspect(tv)}
  },
  rows: rows
}
IO.puts(Jason.encode!(out, pretty: true))
