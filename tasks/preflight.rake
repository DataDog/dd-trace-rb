# Fast local checks mirroring the CI Static Analysis jobs that catch
# most push failures. Full steep type checking stays in CI: a local run
# takes 10+ minutes and the rbs:stale / rbs:missing steps here catch the
# signature-file mistakes that most often break the steep job.
desc "Run the fast CI parity checks: rubocop, standard, rbs:stale, rbs:missing"
task preflight: ["rubocop", "standard", "rbs:stale", "rbs:missing"] do
end
