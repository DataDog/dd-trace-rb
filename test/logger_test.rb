require 'logger'
require 'stringio'
require 'helper'
require 'ddtrace/span'

class LoggerTest < Minitest::Test
  DEFAULT_LOG = Datadog::Logger.log

  def setup
    @buf = StringIO.new
    Datadog::Logger.log = Datadog::Logger.new(@buf)
    Datadog::Logger.log.level = ::Logger::WARN
  end

  def teardown
    Datadog::Logger.log = DEFAULT_LOG
  end

  def test_tracer_logger
    # a logger must be available by default
    assert Datadog::Logger.log
    Datadog::Logger.log.debug('a logger is here!')
    Datadog::Logger.log.info() { 'flash info' } # &block syntax
  end

  def test_tracer_default_debug_mode
    logger = Datadog::Logger.log
    assert_equal(logger.level, Logger::WARN)
  end

  def test_tracer_set_debug_mode
    logger = Datadog::Logger.log

    # enable the debug mode
    Datadog::Logger.debug_logging = true
    assert_equal(logger.level, Logger::DEBUG)

    # revert to production mode
    Datadog::Logger.debug_logging = false
    assert_equal(logger.level, Logger::WARN)
  end

  def test_tracer_set_debug_custom_noop
    # custom logger
    custom_buf = StringIO.new
    custom_logger = Logger.new(custom_buf)
    custom_logger.level = ::Logger::INFO
    Datadog::Logger.log = custom_logger

    Datadog::Logger.debug_logging = false
    assert_equal(custom_logger.level, ::Logger::INFO)
  end

  def test_tracer_logger_override
    assert_equal(false, Datadog::Logger.log.debug?)
    assert_equal(false, Datadog::Logger.log.info?)
    assert_equal(true, Datadog::Logger.log.warn?)
    assert_equal(true, Datadog::Logger.log.error?)
    assert_equal(true, Datadog::Logger.log.fatal?)

    Datadog::Logger.log.debug('never to be seen')
    Datadog::Logger.log.warn('careful here')
    Datadog::Logger.log.error() { 'this does not work' }
    Datadog::Logger.log.error('foo') { 'neither does this' }
    Datadog::Logger.log.progname = 'bar'
    Datadog::Logger.log.add(Logger::WARN, 'add some warning')

    lines = @buf.string.lines

    assert_equal(4, lines.length, 'there should be 4 log messages') if lines.respond_to? :length
    # Test below iterates on lines, this is required for Ruby 1.9 backward compatibility.
    i = 0
    lines.each do |l|
      case i
      when 0
        assert_match(/W,.*WARN -- ddtrace: \[ddtrace\] careful here/, l)
      when 1
        assert_match(
          /E,.*ERROR -- ddtrace: \[ddtrace\] \(.*logger_test.rb\:.*test_tracer_logger_override.*\) this does not work/,
          l
        )
      when 2
        assert_match(
          /E,.*ERROR -- foo: \[ddtrace\] \(.*logger_test.rb\:.*test_tracer_logger_override.*\) neither does this/,
          l
        )
      when 3
        assert_match(/W,.*WARN -- bar: \[bar\] add some warning/, l)
      end
      i += 1
    end
  end

  def test_tracer_logger_override_debug
    Datadog::Logger.log.level = ::Logger::DEBUG

    assert_equal(true, Datadog::Logger.log.debug?)
    assert_equal(true, Datadog::Logger.log.info?)
    assert_equal(true, Datadog::Logger.log.warn?)
    assert_equal(true, Datadog::Logger.log.error?)
    assert_equal(true, Datadog::Logger.log.fatal?)

    Datadog::Logger.log.debug('detailed things')
    Datadog::Logger.log.info() { 'more detailed info' }

    lines = @buf.string.lines

    # Test below iterates on lines, this is required for Ruby 1.9 backward compatibility.
    assert_equal(2, lines.length, 'there should be 2 log messages') if lines.respond_to? :length
    i = 0
    lines.each do |l|
      case i
      when 0
        assert_match(
          /D,.*DEBUG -- ddtrace: \[ddtrace\] \(.*logger_test.rb\:.*test_tracer_logger_override_debug.*\) detailed things/,
          l
        )
      when 1
        assert_match(
          /I,.*INFO -- ddtrace: \[ddtrace\] \(.*logger_test.rb\:.*test_tracer_logger_override_debug.*\) more detailed info/,
          l
        )
      end
      i += 1
    end
  end

  def test_tracer_logger_override_refuse
    buf = StringIO.new

    buf_log = Datadog::Logger.new(buf)

    Datadog::Logger.log = buf_log
    Datadog::Logger.log.level = ::Logger::DEBUG

    Datadog::Logger.log = nil
    assert_equal(buf_log, Datadog::Logger.log)
    Datadog::Logger.log = "this won't work"
    assert_equal(buf_log, Datadog::Logger.log)
  end
end
