#!/usr/bin/env bash
# Restore the book_library fixture to its documented DAY ZERO state.
#
# Day zero = a plain Mix project that declares ash/ash_postgres/igniter as
# deps and NOTHING else: no domain, no resource, no repo, no Application
# module, no migrations, no snapshots, no manufactured mix task. Everything
# else in the tree is manufactured by
# `mix book_library.manufacture` from the ash_manufacture_pack ontology.
#
# This script exists so a qualification run is REPLAYABLE: run 1 must start
# from a known subject, or "run 1 vs run 2" is not a controlled comparison.
#
# It deletes ONLY the enumerated manufactured paths below. It never touches
# deps/, _build/, mix.lock, or anything outside the fixture root.
set -euo pipefail

FIXTURE="${1:?usage: day_zero.sh <path-to-book_library-fixture>}"
# Normalise BEFORE the cd. Every path below is used relative to the fixture
# root, but the mix.exs rewrite at the bottom was passed "$FIXTURE/mix.exs",
# which resolves against the NEW cwd once we are inside the fixture. A
# relative argument therefore deleted the manufactured tree, rewrote the
# config files, and only then died -- a half-reset fixture, not a day-zero
# one. Reproduced with `day_zero.sh test/fixtures/book_library`:
#   FileNotFoundError: ... 'test/fixtures/book_library/mix.exs'
# qualify.sh:39 happens to pass an absolute path, which is why the harness
# never saw this; the usage string promises no such thing.
FIXTURE="$(cd "$FIXTURE" && pwd)"
cd "$FIXTURE"

# --- exact enumerated manufactured paths ----------------------------------
MANUFACTURED=(
  "lib/book_library/application.ex"
  "lib/book_library/repo.ex"
  "lib/book_library/resource.ex"
  "lib/book_library/catalog.ex"
  "lib/book_library/catalog"
  "lib/book_library/circulation.ex"
  "lib/book_library/circulation"
  "lib/mix/tasks"
  "priv/repo"
  "priv/resource_snapshots"
  "test/support"
  "config/runtime.exs"
  ".ggen_igniter"
  ".formatter.exs.bak"
)

for p in "${MANUFACTURED[@]}"; do
  if [ -e "$p" ]; then
    echo "day_zero: removing $p"
    rm -rf "./$p"
  fi
done

# --- day-zero source files (rewritten deterministically) -------------------
# The `cat >` redirections below do not create their parent directory, so a
# tree missing `config/` or `lib/` aborted this script at the first heredoc --
# AFTER the removal loop above had already run. That left the fixture with no
# config/ and no manufactured tree, and every later invocation failed at the
# same line, so the script could not recover the state it exists to restore.
# Reproduced on a tree whose config/ had been removed out of band:
#   day_zero.sh: line 63: config/config.exs: No such file or directory
#   day_zero.sh exit=1
mkdir -p config lib

cat > lib/book_library.ex <<'EOF'
defmodule BookLibrary do
  @moduledoc """
  Day-zero `book_library` fixture (ggen_igniter v26.9.8).

  Intentionally has no Ash domain, resource, repo or Application module.
  Every one of those surfaces is manufactured by the real upstream
  Ash/Igniter generators, composed by `mix book_library.manufacture`, which
  is itself rendered by `ggen_igniter` from
  `test/fixtures/ash_manufacture_pack/`.

  If you are an agent reading this and about to hand-write an Ash resource
  or domain here: don't. See `AGENTS.md` at the repository root.
  """
end
EOF

cat > config/config.exs <<'EOF'
import Config

# Day zero: no domains registered. `mix ash.gen.domain` (composed by
# `mix book_library.manufacture --phase core`) appends to this list;
# `mix ash_postgres.install` (phase base) adds `ecto_repos:`;
# `mix ash.gen.base_resource` (phase base) adds `base_resources:`.
config :book_library, ash_domains: []

config :ash, :include_embedded_source_by_default?, false

import_config "#{config_env()}.exs"
EOF

printf 'import Config\n' > config/dev.exs
printf 'import Config\n' > config/prod.exs
printf 'import Config\n\nconfig :logger, level: :warning\n' > config/test.exs

cat > .formatter.exs <<'EOF'
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
EOF

# --- day-zero mix.exs ------------------------------------------------------
# The four strips below are deliberately ALL still here.
#
# They were suspected of causing the two cold `Compiling 617 files (.ex)` ash
# rebuilds that dominate a qualification run (~34s of ~62s), on the theory that
# stripping deps here and letting phase base re-add them invalidates the build.
# That theory is REFUTED. Measured on this fixture, warming to a compile
# fixpoint before each trial and counting the ash rebuild after the mutation:
#
#   mutation applied to the warm fixture                      ash rebuilt?  cost
#   -------------------------------------------------------   -----------   ----
#   strip all four items, then `mix compile`                   no           1.3s
#   restore all four, then `mix deps.get && mix compile`       no           2.5s
#   `touch mix.exs` (mtime only, content unchanged)            no           0.6s
#   `touch config/config.exs` (mtime only)                     no           0.6s
#   change `config :book_library, ash_domains:`                no           0.9s
#   add a `config :ash, <key ash never reads>`                 no           0.9s
#   change `config :ash, :include_embedded_source_by_default?` YES         17.2s
#
# The rebuild is neither mtime-driven nor mix.exs-driven. Elixir invalidates
# per `Application.compile_env/3` KEY, and ash reads that key into a module
# attribute of Ash.EmbeddableType, which nearly all of ash depends on:
#   deps/ash/lib/ash/embeddable_type.ex:8-12
#
# The real cost centre is the config/config.exs rewrite ABOVE, not this block.
# `mix ash.install` writes 13 `config :ash` keys (ash.install.ex:176-208); day
# zero carries one of them. So the run pays one 617-file rebuild resetting to
# day zero, and a second when phase base puts the other twelve back.
#
# That cost is not removable here. Pre-seeding ash.install's config block would
# start the fixture from ash.install's own output: the fixture would no longer
# be at day zero, and the harness would stop observing the manufacturing step
# it exists to observe. The controlled comparison outranks the 34s.
#
# The strips are therefore FREE -- they buy no rebuild either way -- and they
# keep day zero genuinely pre-install, so spark.install's add-dep branch
# (deps/spark/lib/mix/tasks/spark.install.ex:29-32) is really taken here rather
# than short-circuiting on an already-present dep.
python3 - "$FIXTURE/mix.exs" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
# Day zero has no Application module, so no `mod:` and no ash.setup aliases.
s = s.replace(",\n      mod: {BookLibrary.Application, []}", "")
s = re.sub(r'\n  defp aliases\(\) do\n.*?\n  end\n', '\n', s, flags=re.S)
s = re.sub(r'\n\s*aliases: aliases\(\),?', '', s)
s = re.sub(r',(\s*\n\s*\])', r'\1', s)
s = s.replace('      {:sourceror, "~> 1.8", only: [:dev, :test]},\n', '')
s = re.sub(r',\n\s*consolidate_protocols: Mix\.env\(\) != :dev', '', s)
open(p, 'w').write(s)
PY

echo "day_zero: fixture restored"
find lib priv config -type f 2>/dev/null | sort
