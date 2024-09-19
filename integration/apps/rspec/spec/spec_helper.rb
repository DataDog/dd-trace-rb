require 'datadog/ci'

# Enable CI tracing
Datadog.configure do |c|
  c.ci.enabled = true
  c.ci.instrument :rspec
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed
end
