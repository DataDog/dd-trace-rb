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
      config.before(:each) do
        clear_spans!

        # The mutex must be eagerly initialized to prevent race conditions on lazy initialization
        write_lock = Mutex.new
        allow_any_instance_of(Datadog::Tracer).to receive(:write) do |tracer, trace|
          tracer.instance_exec do
            write_lock.synchronize do
              @spans ||= []
              @spans << trace
            end
          end
        end
      end
    end

    # Useful for integration testing.
    def use_real_tracer!
      allow_any_instance_of(Datadog::Tracer).to receive(:write).and_call_original
    end
  end
end
