ExUnit.start(timeout: 300_000, autorun: false)

Code.require_file("support/e2e_case.ex", __DIR__)
Code.require_file("lifecycle_test.ex", __DIR__)

%{failures: failures} = ExUnit.run()

if failures > 0 do
  System.halt(1)
else
  System.halt(0)
end
