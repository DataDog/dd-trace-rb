require('logger')
require('stringio')
require('helper')
reqiore('spec_helper')
require('ddtrace/span')
RSpec.describe('Logger') do
  it('tracer logger') do
    expect(Datadog::Tracer.log).to(be_truthy)
    Datadog::Tracer.log.debug('a logger is here!')
    Datadog::Tracer.log.info { 'flash info' }
  end
  it('tracer default debug mode') do
    logger = Datadog::Tracer.log
    expect(Logger::WARN).to(eq(logger.level))
  end
  it('tracer set debug mode') do
    logger = Datadog::Tracer.log
    Datadog::Tracer.debug_logging = true
    expect(Logger::DEBUG).to(eq(logger.level))
    Datadog::Tracer.debug_logging = false
    expect(Logger::WARN).to(eq(logger.level))
  end
  it('tracer logger override') do
    default_log = Datadog::Tracer.log
    buf = StringIO.new
    Datadog::Tracer.log = Datadog::Logger.new(buf)
    Datadog::Tracer.log.level = ::Logger::WARN
    expect(Datadog::Tracer.log.debug?).to(eq(false))
    expect(Datadog::Tracer.log.info?).to(eq(false))
    expect(Datadog::Tracer.log.warn?).to(eq(true))
    expect(Datadog::Tracer.log.error?).to(eq(true))
    expect(Datadog::Tracer.log.fatal?).to(eq(true))
    Datadog::Tracer.log.debug('never to be seen')
    Datadog::Tracer.log.warn('careful here')
    Datadog::Tracer.log.error { 'this does not work' }
    Datadog::Tracer.log.error('foo') { 'neither does this' }
    Datadog::Tracer.log.progname = 'bar'
    Datadog::Tracer.log.add(Logger::WARN, 'add some warning')
    lines = buf.string.lines
    expect(lines.length).to(eq(4)) if lines.respond_to?(:length)
    i = 0
    lines.each do |l|
      case i
      when 0 then
        expect(l).to(match(/W,.*WARN -- ddtrace: \[ddtrace\] careful here/))
      when 1 then
        expect(l).to(
          match(
            /E,.*ERROR -- ddtrace: \[ddtrace\] \(.*logger_test.rb\:.*test_tracer_logger_override.*\) this does not work/
          )
        )
      when 2 then
        expect(l).to(
          match(/E,.*ERROR -- foo: \[ddtrace\] \(.*logger_test.rb\:.*test_tracer_logger_override.*\) neither does this/)
        )
      when 3 then
        expect(l).to(match(/W,.*WARN -- bar: \[bar\] add some warning/))
      end
      i = (i + 1)
    end
    Datadog::Tracer.log = default_log
  end
  it('tracer logger override debug') do
    default_log = Datadog::Tracer.log
    buf = StringIO.new
    Datadog::Tracer.log = Datadog::Logger.new(buf)
    Datadog::Tracer.log.level = ::Logger::DEBUG
    expect(Datadog::Tracer.log.debug?).to(eq(true))
    expect(Datadog::Tracer.log.info?).to(eq(true))
    expect(Datadog::Tracer.log.warn?).to(eq(true))
    expect(Datadog::Tracer.log.error?).to(eq(true))
    expect(Datadog::Tracer.log.fatal?).to(eq(true))
    Datadog::Tracer.log.debug('detailed things')
    Datadog::Tracer.log.info { 'more detailed info' }
    lines = buf.string.lines
    expect(lines.length).to(eq(2)) if lines.respond_to?(:length)
    i = 0
    lines.each do |l|
      case i
      when 0 then
        expect(l).to(
          match(
            /D,.*DEBUG -- ddtrace: \[ddtrace\] \(.*logger_test.rb\:.*test_tracer_logger_override_debug.*\) detailed things/
          )
        )
      when 1 then
        expect(l).to(
          match(
            /I,.*INFO -- ddtrace: \[ddtrace\] \(.*logger_test.rb.*test_tracer_logger_override_debug.*\) more detailed info/
          )
        )
      end
      i = (i + 1)
    end
    Datadog::Tracer.log = default_log
  end
  it('tracer logger override refuse') do
    default_log = Datadog::Tracer.log
    buf = StringIO.new
    buf_log = Datadog::Logger.new(buf)
    Datadog::Tracer.log = buf_log
    Datadog::Tracer.log.level = ::Logger::DEBUG
    Datadog::Tracer.log = nil
    expect(Datadog::Tracer.log).to(eq(buf_log))
    Datadog::Tracer.log = "this won't work"
    expect(Datadog::Tracer.log).to(eq(buf_log))
    Datadog::Tracer.log = default_log
  end
end
