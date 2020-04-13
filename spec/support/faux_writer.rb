require 'ddtrace/writer'
require 'support/faux_transport'
require 'support/trace_buffer'

# FauxWriter is a dummy writer that buffers spans locally.
class FauxWriter < Datadog::Writer
  attr_reader \
    :buffer

  def initialize(options = {})
    options[:transport] ||= FauxTransport.new
    options[:call_original] ||= true
    @options = options
    @buffer = TestTraceBuffer.new

    super if options[:call_original]
  end

  def write(trace)
    buffer << trace
    super(trace) if @options[:call_original]
  end
end
