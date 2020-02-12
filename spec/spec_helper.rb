$LOAD_PATH.unshift File.expand_path('../../', __FILE__)
$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'pry'
require 'rspec/collection_matchers'
require 'webmock/rspec'
require 'climate_control'

require 'ddtrace/encoding'
require 'ddtrace/tracer'
require 'ddtrace/span'

require 'support/configuration_helpers'
require 'support/container_helpers'
require 'support/faux_transport'
require 'support/faux_writer'
require 'support/health_metric_helpers'
require 'support/http_helpers'
require 'support/log_helpers'
require 'support/metric_helpers'
require 'support/network_helpers'
require 'support/span_helpers'
require 'support/spy_transport'
require 'support/synchronization_helpers'
require 'support/tracer_helpers'

begin
  # Ignore interpreter warnings from external libraries
  require 'warning'
  Warning.ignore([:method_redefined, :not_reached, :unused_var], %r{.*/gems/[^/]*/lib/})
rescue LoadError
  puts 'warning suppressing gem not available, external library warnings will be displayed'
end

WebMock.allow_net_connect!
WebMock.disable!

RSpec.configure do |config|
  config.include ConfigurationHelpers
  config.include ContainerHelpers
  config.include HealthMetricHelpers
  config.include HttpHelpers
  config.include LogHelpers
  config.include MetricHelpers
  config.include NetworkHelpers
  config.include SpanHelpers
  config.include SynchronizationHelpers
  config.include TracerHelpers

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

  # require 'stackprof'
  # config.around(:each) do |example|
  #   puts example.full_description
  #   path = "/tmp/stackprof-cpu-test-#{URI.encode_www_form_component example.full_description}.dump"
  #   StackProf.run(raw: true, aggregate: false, mode: :cpu, interval: 10, out: path.to_s) do
  #     example.run
  #   end
  # end

  # require 'ruby-prof'
  # config.around(:each) do |example|
  #   RubyProf.measure_mode = RubyProf::ALLOCATIONS
  #   RubyProf.start
  #
  #   example.run
  #
  #   result = RubyProf.stop
  #
  #   # printer = RubyProf::FlatPrinter.new(result)
  #   # printer.print(STDOUT)
  #
  #   printer = RubyProf::GraphHtmlPrinter.new(result)
  #   printer.print(File.open('/tmp/prof.html', 'w'), :min_percent=>0)
  #
  #   # printer = RubyProf::GraphPrinter.new(result)
  #   # printer.print(STDOUT, {})
  # end

  require 'rspec-benchmark'
  # config.include RSpec::Benchmark::Matchers
end
