require 'logger'
require 'helper'
require 'ddtrace/span'

class LoggerTest < Minitest::Test
  def test_tracer_logger
    # a logger must be available by default
    assert Datadog::Tracer.log
    Datadog::Tracer.log.debug('a logger is here!')
  end

  def test_tracer_default_debug_mode
    logger = Datadog::Tracer.log
    assert_equal(logger.level, Logger::WARN)
  end

  def test_tracer_set_debug_mode
    logger = Datadog::Tracer.log

    # enable the debug mode
    Datadog::Tracer.debug_logging = true
    assert_equal(logger.level, Logger::DEBUG)

    # revert to production mode
    Datadog::Tracer.debug_logging = false
    assert_equal(logger.level, Logger::WARN)
  end
end
