require 'logger'
require 'stringio'
require 'helper'
require 'ddtrace/span'

class LoggerTest < Minitest::Test
  def test_tracer_logger
    # a logger must be available by default
    assert Datadog::Tracer.log
    Datadog::Tracer.log.debug('a logger is here!')
    Datadog::Tracer.log.info() { 'flash info' } # &block syntax
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

  def test_tracer_logger_override
    default_log = Datadog::Tracer.log

    buf = StringIO.new

    Datadog::Tracer.log = Datadog::Logger.new(buf)
    Datadog::Tracer.log.level = ::Logger::WARN

    assert_equal(false, Datadog::Tracer.log.debug?)
    assert_equal(false, Datadog::Tracer.log.info?)
    assert_equal(true, Datadog::Tracer.log.warn?)
    assert_equal(true, Datadog::Tracer.log.error?)
    assert_equal(true, Datadog::Tracer.log.fatal?)

    Datadog::Tracer.log.debug('never to be seen')
    Datadog::Tracer.log.warn('careful here')
    Datadog::Tracer.log.error() { 'this does not work' }
    Datadog::Tracer.log.error('mmm') { 'neither does this' }

    lines = buf.string.lines

    assert_equal(3, lines.length, 'there should be 3 log messages')
    assert_match(/W,.*WARN -- ddtrace: careful here/, lines[0])
    assert_match(/E,.*ERROR -- ddtrace: this does not work/, lines[1])
    assert_match(/E,.*ERROR -- mmm: neither does this/, lines[2])

    Datadog::Tracer.log = default_log
  end

  def test_tracer_logger_override_debug
    default_log = Datadog::Tracer.log

    buf = StringIO.new

    Datadog::Tracer.log = Datadog::Logger.new(buf)
    Datadog::Tracer.log.level = ::Logger::DEBUG

    assert_equal(true, Datadog::Tracer.log.debug?)
    assert_equal(true, Datadog::Tracer.log.info?)
    assert_equal(true, Datadog::Tracer.log.warn?)
    assert_equal(true, Datadog::Tracer.log.error?)
    assert_equal(true, Datadog::Tracer.log.fatal?)

    Datadog::Tracer.log.debug('detailed things')
    Datadog::Tracer.log.info() { 'more detailed info' }

    lines = buf.string.lines

    assert_equal(2, lines.length, 'there should be 3 log messages')
    assert_match(
      /D,.*DEBUG -- ddtrace: \(.*logger_test.rb\:.*test_tracer_logger_override_debug.*\) detailed things/,
      lines[0]
    )
    assert_match(
      /I,.*INFO -- ddtrace: \(.*logger_test.rb\:.*test_tracer_logger_override_debug.*\) more detailed info/,
      lines[1]
    )

    Datadog::Tracer.log = default_log
  end
end
