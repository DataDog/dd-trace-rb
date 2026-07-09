# frozen_string_literal: true

require 'yaml'

# See rubocop/standard_overrides.rubocop.yml for why these cops need to run outside of standard.
#
# We pass the cops explicitly via --only, derived from the config file's own cop keys, rather
# than setting AllCops: DisabledByDefault: true in the config: any `# rubocop:disable`/
# `# rubocop:enable` comment for ANY cop, anywhere in the codebase, forces that cop to run
# file-wide regardless of DisabledByDefault (RuboCop needs to check whether the directive is
# redundant). With 300+ such comments in this codebase, that made DisabledByDefault produce
# unpredictable stray offenses. --only has no such failure mode.
def run_standard_override_rubocop(*extra_args)
  standard_override_config = 'rubocop/standard_overrides.rubocop.yml'
  standard_override_cops = YAML.load_file(standard_override_config).keys.select { |key| key.include?('/') }

  sh 'bundle',
    'exec',
    'rubocop',
    '--config', standard_override_config,
    '--only', standard_override_cops.join(','),
    *extra_args
end

desc 'Check cops that standard disables or misconfigures (see rubocop/standard_overrides.rubocop.yml)'
task :rubocop do
  run_standard_override_rubocop
end

desc 'Autocorrect cops that standard disables or misconfigures (see rubocop/standard_overrides.rubocop.yml)'
task :"rubocop:fix" do
  run_standard_override_rubocop '--autocorrect'
end
