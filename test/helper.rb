require 'minitest'
require 'minitest/autorun'

require 'tracer'


def get_test_tracer()
  return Datadog::Tracer.new({:writer => FauxWriter.new})
end


class FauxWriter

  def initialize()
    @buff = []
  end

  def write(span)
    @buff << span
  end

  def spans()
    buff = @buff
    @buff = []
    return buff
  end

end
