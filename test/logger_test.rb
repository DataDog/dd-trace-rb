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

  def test_tracer_set_debug_custom_noop
    default_log = Datadog::Tracer.log

    # custom logger
    buf = StringIO.new
    custom_logger = Logger.new(buf)
    custom_logger.level = ::Logger::INFO
    Datadog::Tracer.log = custom_logger

    Datadog::Tracer.debug_logging = false
    assert_equal(custom_logger.level, ::Logger::INFO)

    Datadog::Tracer.log = default_log
  end  

  # rubocop:disable Metrics/MethodLength
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
    Datadog::Tracer.log.error('foo') { 'neither does this' }
    Datadog::Tracer.log.progname = 'bar'
    Datadog::Tracer.log.add(Logger::WARN, 'add some warning')

    lines = buf.string.lines

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

    Datadog::Tracer.log = default_log
  end

  def test_tracer_logger_override_refuse
    default_log = Datadog::Tracer.log

    buf = StringIO.new

    buf_log = Datadog::Logger.new(buf)

    Datadog::Tracer.log = buf_log
    Datadog::Tracer.log.level = ::Logger::DEBUG

    Datadog::Tracer.log = nil
    assert_equal(buf_log, Datadog::Tracer.log)
    Datadog::Tracer.log = "this won't work"
    assert_equal(buf_log, Datadog::Tracer.log)

    Datadog::Tracer.log = default_log
  end
end
