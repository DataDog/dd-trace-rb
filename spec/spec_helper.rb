$LOAD_PATH.unshift File.expand_path('../../', __FILE__)
$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'pry'
require 'rspec/collection_matchers'
require 'webmock/rspec'
require 'climate_control'

require 'ddtrace/encoding'
require 'ddtrace/transport'
require 'ddtrace/tracer'
require 'ddtrace/span'

# require 'support/test_access_patch'
require 'support/faux_writer'
require 'support/faux_transport'
require 'support/spy_transport'
require 'support/tracer_helpers'
# require 'support/rails_active_record_helpers'
require 'support/configuration_helpers'
require 'support/synchronization_helpers'
require 'support/log_helpers'
require 'support/http_helpers'
require 'support/metric_helpers'

WebMock.allow_net_connect!
WebMock.disable!

RSpec.configure do |config|
  config.include TracerHelpers
  config.include HttpHelpers
  config.include ConfigurationHelpers
  config.include SynchronizationHelpers
  config.include LogHelpers
  config.include MetricHelpers

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.warnings = true
  config.order = :random
end
