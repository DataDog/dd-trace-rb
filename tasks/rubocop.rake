# frozen_string_literal: true

# See rubocop/standard_overrides.rubocop.yml for why these cops need to run outside of standard.

def run_standard_override_rubocop(*extra_args)
  standard_override_cops = 'Layout/LeadingCommentSpace,Style/FrozenStringLiteralComment'
  standard_override_config = 'rubocop/standard_overrides.rubocop.yml'
  sh 'bundle',
    'exec',
    'rubocop',
    '--only', standard_override_cops,
    '--config', standard_override_config,
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
