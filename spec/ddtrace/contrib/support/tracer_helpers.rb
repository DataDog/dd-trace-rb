require 'ddtrace/tracer'
require 'ddtrace/span'
require 'support/faux_writer'

module Contrib
  # Contrib-specific tracer helpers.
  # For contrib, we only allow one tracer to be active:
  # the global +Datadog.tracer+.
  module TracerHelpers
    # Returns the current tracer instance
    def tracer
      Datadog.tracer
    end

    # Returns spans and caches it (similar to +let(:spans)+).
    def spans
      @spans ||= fetch_spans
    end

    # Retrieves and sorts all spans in the current tracer instance.
    # This method does not cache its results.
    def fetch_spans(tracer = self.tracer)
      spans = tracer.instance_variable_get(:@spans) || []
      spans.flatten.sort! do |a, b|
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
    def clear_spans!
      tracer.instance_variable_set(:@spans, [])

      @spans = nil
      @span = nil
    end

    RSpec.configure do |config|
      # Capture spans from the global tracer
      config.before do
        # DEV `*_any_instance_of` has concurrency issues when running with parallelism (e.g. JRuby).
        # DEV Single object `allow` and `expect` work as intended with parallelism.
        allow(Datadog::Tracer).to receive(:new).and_wrap_original do |method, *args, &block|
          instance = method.call(*args, &block)

          # The mutex must be eagerly initialized to prevent race conditions on lazy initialization
          write_lock = Mutex.new
          allow(instance).to receive(:write) do |trace|
            instance.instance_exec do
              write_lock.synchronize do
                @spans ||= []
                @spans << trace
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
          Datadog.tracer.shutdown!
        end
      end
    end

    # Useful for integration testing.
    def use_real_tracer!
      @use_real_tracer = true
      allow(Datadog::Tracer).to receive(:new).and_call_original
    end
  end
end
