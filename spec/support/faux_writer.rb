require 'datadog/tracing/writer'

require 'support/faux_transport'

# FauxWriter is a dummy writer that buffers spans locally.
class FauxWriter < Datadog::Tracing::Writer
  def initialize(options = {})
    options[:transport] ||= FauxTransport.new
    options[:call_original] ||= true
    @options = options

    super if options[:call_original]
    @mutex = Mutex.new

    # easy access to registered components
    @traces = []
  end

  def write(trace)
    @mutex.synchronize do
      super(trace) if @options[:call_original]
      @traces << trace
    end
  end

  def traces(action = :clear)
    traces = @traces
    @traces = [] if action == :clear
    traces
  end

  def spans(action = :clear)
    @mutex.synchronize do
      traces = @traces
      @traces = [] if action == :clear
      spans = traces.collect(&:spans).flatten
      # sort the spans to avoid test flakiness

      spans.sort! do |a, b|
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
  end
end
