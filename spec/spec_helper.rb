$LOAD_PATH.unshift File.expand_path('..', __dir__)
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'pry'
require 'rspec/collection_matchers'
require 'webmock/rspec'
require 'climate_control'

if (ENV['SKIP_SIMPLECOV'] != '1') && !RSpec.configuration.files_to_run.all? { |path| path.include?('/benchmark/') }
  # +SimpleCov.start+ must be invoked before any application code is loaded
  require 'simplecov'
  SimpleCov.start do
    formatter SimpleCov::Formatter::SimpleFormatter
  end
end

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
require 'support/platform_helpers'
require 'support/span_helpers'
require 'support/spy_transport'
require 'support/synchronization_helpers'
require 'support/test_helpers'
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
  config.include TestHelpers
  config.include TracerHelpers

  config.include TestHelpers::RSpec::Integration, :integration

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
  config.filter_run focus: true
  config.run_all_when_everything_filtered = true

  if config.files_to_run.one?
    # Use the documentation formatter for detailed output,
    # unless a formatter has already been configured
    # (e.g. via a command-line flag).
    config.default_formatter = 'doc'
  end

  # Check for leaky test resources.
  #
  # Execute this after the test has finished
  # teardown and mock verifications.
  #
  # Changing this to `config.after(:each)` would
  # put this code inside the test scope, interfering
  # with the test execution.
  #
  # rubocop:disable Style/GlobalVars
  config.around do |example|
    example.run.tap do
      # Stop reporting on background thread leaks after too many
      # successive failures. The output is very verbose and, at that point,
      # it's better to work on fixing the very first occurrences.
      $background_thread_leak_reports ||= 0
      if $background_thread_leak_reports >= 10
        unless $background_thread_leak_warned ||= false
          warn RSpec::Core::Formatters::ConsoleCodes.wrap(
            "Too many leaky thread reports! Suppressing further reports.\n" \
            'Consider addressing the previously reported leaks before proceeding.',
            :red
          )

          $background_thread_leak_warned = true
        end

        next
      end

      # Exclude acceptable background threads
      background_threads = Thread.list.reject do |t|
        group_name = t.group.instance_variable_get(:@group_name) if t.group.instance_variable_defined?(:@group_name)
        backtrace = t.backtrace || []

        # Current thread
        t == Thread.current ||
          # Thread has shut down, but we caught it right as it was still alive
          !t.alive? ||
          # Internal JRuby thread
          defined?(JRuby) && JRuby.reference(t).native_thread.name == 'Finalizer' ||
          # WEBrick singleton thread for handling timeouts
          backtrace.find { |b| b.include?('/webrick/utils.rb') } ||
          # WEBrick server thread
          t[:WEBrickSocket] ||
          # Rails connection reaper
          backtrace.find { |b| b.include?('lib/active_record/connection_adapters/abstract/connection_pool.rb') } ||
          # Ruby JetBrains debugger
          (t.class.name && t.class.name.include?('DebugThread')) ||
          # Categorized as a known leaky thread
          !group_name.nil? ||
          # Internal TruffleRuby thread, defined in
          # https://github.com/oracle/truffleruby/blob/02f568556ca4dd9056b0114b750ab848ac52943b/src/main/java/org/truffleruby/core/ReferenceProcessingService.java#L221
          RUBY_ENGINE == 'truffleruby' && t.to_s.include?('Ruby-reference-processor')
      end

      unless background_threads.empty?
        # TODO: Temporarily disabled for `spec/ddtrace/workers`
        # was meaningful changes are required to address clean
        # teardown in those tests.
        # They currently flood the output, making our test
        # suite output unreadable.
        if example.file_path.start_with?('./spec/ddtrace/workers/')
          RSpec.warning("FIXME: #{example.file_path}:#{example.metadata[:line_number]} is leaking threads")
          next
        end

        info = background_threads.each_with_index.flat_map do |t, idx|
          backtrace = t.backtrace
          if backtrace.nil? && t.alive? # Maybe the thread hasn't run yet? Let's give it a second chance
            Thread.pass
            backtrace = t.backtrace
          end
          if backtrace.nil? || backtrace.empty?
            backtrace =
              if t.alive?
                ['(Not available. Possibly a native thread.)']
              else
                ['(Thread finished before we could collect a backtrace)']
              end
          end

          caller = t.instance_variable_get(:@caller) || ['(Not available. Possibly a native thread.)']
          [
            "#{idx + 1}: #{t} (#{t.class.name})",
            'Thread Creation Site:',
            caller.map { |l| "\t#{l}" }.join("\n"),
            'Thread Backtrace:',
            backtrace.map { |l| "\t#{l}" }.join("\n"),
            "\n"
          ]
        end.join("\n")

        # Warn about leakly thread
        warn RSpec::Core::Formatters::ConsoleCodes.wrap(
          "Spec leaked #{background_threads.size} threads in \"#{example.full_description}\".\n" \
          "Ensure all threads are terminated when test finishes.\n" \
          "For help fixing this issue, see \"Ensuring tests don't leak resources\" in docs/DevelopmentGuide.md.\n" \
          "\n" \
          "#{info}",
          :yellow
        )

        $background_thread_leak_reports += 1
      end
    end
  end
  # rubocop:enable Style/GlobalVars

  # Closes the global testing tracer.
  #
  # Execute this after the test has finished
  # teardown and mock verifications.
  #
  # Changing this to `config.after(:each)` would
  # put this code inside the test scope, interfering
  # with the test execution.
  config.around do |example|
    example.run.tap do
      tracer_shutdown!
    end
  end
end

# Stores the caller thread backtrace,
# To allow for leaky threads to be traced
# back to their creation point.
module DatadogThreadDebugger
  # DEV: we have to use an explicit `block`, argument
  # instead of the implicit `yield` call, as calling
  # `yield` here crashes the Ruby VM in Ruby < 2.2.
  def initialize(*args, &block)
    @caller = caller
    wrapped = lambda do |*thread_args|
      block.call(*thread_args) # rubocop:disable Performance/RedundantBlockCall
    end
    wrapped.ruby2_keywords if wrapped.respond_to?(:ruby2_keywords, true)

    super(*args, &wrapped)
  end

  ruby2_keywords :initialize if respond_to?(:ruby2_keywords, true)
end

Thread.prepend(DatadogThreadDebugger)

# Helper matchers
RSpec::Matchers.define_negated_matcher :not_be, :be
