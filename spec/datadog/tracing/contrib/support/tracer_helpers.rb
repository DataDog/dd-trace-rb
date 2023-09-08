require 'support/faux_writer'
require 'support/network_helpers'

require 'datadog/tracing/tracer'
require 'datadog/tracing/span'
require 'datadog/tracing/sync_writer'

module Contrib
  include NetworkHelpers
  # Contrib-specific tracer helpers.
  # For contrib, we only allow one tracer to be active:
  # the global tracer in +Datadog::Tracing+.
  module TracerHelpers
    # Returns the current tracer instance
    def tracer
      Datadog::Tracing.send(:tracer)
    end

    # Returns spans and caches it (similar to +let(:spans)+).
    def traces
      @traces ||= fetch_traces
    end

    # Returns spans and caches it (similar to +let(:spans)+).
    def spans
      @spans ||= fetch_spans
    end

    # Retrieves all traces in the current tracer instance.
    # This method does not cache its results.
    def fetch_traces(tracer = self.tracer)
      (tracer.instance_variable_defined?(:@traces) && tracer.instance_variable_get(:@traces)) || []
    end

    # Retrieves and sorts all spans in the current tracer instance.
    # This method does not cache its results.
    def fetch_spans(tracer = self.tracer)
      traces = fetch_traces(tracer)
      traces.collect(&:spans).flatten.sort! do |a, b|
        if a.name == b.name
          if a.resource == b.resource
            if a.start_time == b.start_time
              a.end_time <=> b.end_time
            else
              a.start_time <=> b.start_time
            end
          else
            a.resource <=> b.resource
          end
        else
          a.name <=> b.name
        end
      end
    end

    # Remove all traces from the current tracer instance and
    # busts cache of +#spans+ and +#span+.
    def clear_traces!
      tracer.instance_variable_set(:@traces, [])

      @traces = nil
      @trace = nil
      @spans = nil
      @span = nil
    end

    RSpec.configure do |config|
      # Capture spans from the global tracer
      config.before do
        # DEV `*_any_instance_of` has concurrency issues when running with parallelism (e.g. JRuby).
        # DEV Single object `allow` and `expect` work as intended with parallelism.
        allow(Datadog::Tracing::Tracer).to receive(:new).and_wrap_original do |method, **args, &block|
          instance = method.call(**args, &block)

          # The mutex must be eagerly initialized to prevent race conditions on lazy initialization
          write_lock = Mutex.new
          allow(instance).to receive(:write) do |trace|
            instance.instance_exec do
              write_lock.synchronize do
                @traces ||= []
                @traces << trace
              end
            end
          end
          instance
        end
      end

      # Execute shutdown! after the test has finished
      # teardown and mock verifications.
      #
      # Changing this to `config.after(:each)` would
      # put shutdown! inside the test scope, interfering
      # with mock assertions.
      config.around do |example|
        example.run.tap do
          Datadog::Tracing.shutdown!
        end
      end

      config.after do
        traces = fetch_traces(tracer)
        unless traces.empty?
          if tracer.respond_to?(:writer) && tracer.writer.transport.client.api.adapter.respond_to?(:hostname) && # rubocop:disable Style/SoleNestedConditional
              tracer.writer.transport.client.api.adapter.hostname == NetworkHelpers::TEST_AGENT_HOST
            transport_options = {
              adapter: :net_http,
              hostname: NetworkHelpers::TEST_AGENT_HOST,
              port: NetworkHelpers::TEST_AGENT_PORT,
              timeout: 30
            }
            traces.each do |trace|
              # write traces after the test to the agent in order to not mess up assertions
              # remake syncwriter instance for each flush to prevent headers from being overrwritten
              sync_writer = Datadog::Tracing::SyncWriter.new(transport_options: transport_options)
              sync_writer.transport.client.api.headers['X-Datadog-Trace-Env-Variables'] = parse_tracer_config
              sync_writer.write(trace)
            end
          end
        end
      end
    end

    # Useful for integration testing.
    def use_real_tracer!
      @use_real_tracer = true
      allow(Datadog::Tracing::Tracer).to receive(:new).and_call_original
    end
  end
end
