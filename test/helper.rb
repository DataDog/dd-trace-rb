require 'minitest'
require 'minitest/autorun'

require 'ddtrace/encoding'
require 'ddtrace/transport'
require 'ddtrace/tracer'
require 'ddtrace/buffer'
require 'ddtrace/span'

# Return a test tracer instance with a faux writer.
def get_test_tracer
  Datadog::Tracer.new(writer: FauxWriter.new)
end

# FauxWriter is a dummy writer that buffers spans locally.
class FauxWriter < Datadog::Writer
  def initialize
    super(transport: FauxTransport.new(HOSTNAME, PORT))

    # easy access to registered components
    @spans = []
    @services = {}
  end

  def write(trace, services)
    super(trace, services)
    @spans << trace
    @services = services
  end

  def spans
    spans = @spans
    @spans = []
    spans.flatten
  end
end

# FauxTransport is a dummy HTTPTransport that doesn't send data to an agent.
class FauxTransport < Datadog::HTTPTransport
  def send(*)
    # noop
  end
end
