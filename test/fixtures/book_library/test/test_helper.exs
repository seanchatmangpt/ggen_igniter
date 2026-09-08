# Day zero (ticket 01): no Repo exists yet, so no Ecto sandbox mode is set
# here. `mix ash_postgres.install` (matrix row 11) rewrites this file via
# setup_data_case/1 when it creates BookLibrary.Repo.
ExUnit.start()
