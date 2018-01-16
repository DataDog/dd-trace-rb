require 'ddtrace/writer'

require 'support/faux_transport'

# FauxWriter is a dummy writer that buffers spans locally.
class FauxWriter < Datadog::Writer
  def initialize(options = {})
    options[:transport] ||= FauxTransport.new(HOSTNAME, PORT)
    super
    @mutex = Mutex.new

    # easy access to registered components
    @spans = []
    @services = {}
  end

  def write(trace, services)
    @mutex.synchronize do
      super(trace, services)
      @spans << trace
      @services = @services.merge(services) unless services.empty?
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

  def services
    @mutex.synchronize do
      services = @services
      @services = {}
      services
    end
  end
end
