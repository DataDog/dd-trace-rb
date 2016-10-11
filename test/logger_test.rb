require 'logger'
require 'helper'
require 'ddtrace/span'

class LoggerTest < Minitest::Test
  def test_tracer_logger
    # a logger must be available by default
    assert Datadog::Tracer.log
    Datadog::Tracer.log.debug('a logger is here!')
  end
end
