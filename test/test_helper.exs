{:ok, _} = Application.ensure_all_started(:tesla)
{:ok, _} = Finch.start_link(name: GgenIgniter.Finch)

ExUnit.start()
