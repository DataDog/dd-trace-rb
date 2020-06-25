require 'ddtrace/writer'

require 'support/faux_transport'

# FauxWriter is a dummy writer that buffers spans locally.
class FauxWriter < Datadog::Writer
  def initialize(options = {})
    options[:transport] ||= FauxTransport.new
    options[:call_original] ||= true
    @options = options

    super if options[:call_original]
    @mutex = Mutex.new

    # easy access to registered components
    @spans = []
  end

  def write(trace)
    @mutex.synchronize do
      super(trace) if @options[:call_original]
      @spans << trace
    end
  end

  def spans(action = :clear)
    @mutex.synchronize do
      spans = @spans
      @spans = [] if action == :clear
      spans.flatten!
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

  def trace0_spans
    @mutex.synchronize do
      return [] unless @spans
      return [] if @spans.empty?
      spans = @spans[0]
      @spans = @spans[1..@spans.size]
      spans
    end
  end
end
