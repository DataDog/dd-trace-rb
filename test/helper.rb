require 'minitest'
require 'minitest/autorun'

require 'ddtrace/encoding'
require 'ddtrace/tracer'
require 'ddtrace/span'

# Return a test tracer instance with a faux writer.
def get_test_tracer
  Datadog::Tracer.new(writer: FauxWriter.new)
end

# FauxWriter is a dummy writer that buffers spans locally.
class FauxWriter
  def initialize
    @buff = []
  end

  def write(spans)
    # Ensure all of our test spans can be encoded to catch weird errors.
    Datadog::Encoding.encode_spans(spans)

    @buff.concat(spans)
  end

  def spans
    buff = @buff
    @buff = []
    buff
  end
end

# Return a hash mapping the given spans by name.
def spans_by_name(spans)
  n = {}
  spans.each do |s|
    n[s.name] = s
  end
  n
end
