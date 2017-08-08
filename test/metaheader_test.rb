require 'helper'
require 'ddtrace'
require 'ddtrace/tracer'
require 'stringio'
require 'thread'
require 'webrick'

class MetaHeaderTest < Minitest::Test
  TEST_PORT = 6219
  EXPECTED_META_LANG = 'ruby'.freeze
  EXPECTED_META_LANG_VERSION = RUBY_VERSION
  # typical lang interpreter would be 'ruby-x86_64-darwin16.4.0'
  EXPECTED_META_LANG_INTEPRETER = defined?(RUBY_ENGINE) ? RUBY_ENGINE + '-' + RUBY_PLATFORM : 'ruby-' + RUBY_PLATFORM
  EXPECTED_META_TRACER_VERSION = Datadog::VERSION::STRING

  # rubocop:disable Metrics/MethodLength
  def setup
    @log_buf = StringIO.new
    log = WEBrick::Log.new @log_buf
    access_log = [
      [@log_buf, WEBrick::AccessLog::COMBINED_LOG_FORMAT]
    ]

    @server = WEBrick::HTTPServer.new Port: TEST_PORT, Logger: log, AccessLog: access_log

    @server.mount_proc '/' do |req, res|
      res.body = '{}'
      ['datadog-meta-lang',
       'datadog-meta-lang-version',
       'datadog-meta-lang-interpreter',
       'datadog-meta-tracer-version'].each do |k|
        v = req.header[k]
        if v.nil?
          e = "#{k} is nil"
          puts e
          raise e
        end
        next unless v.empty?
        e = "#{k} is empty"
        puts e
        raise e
      end

      if EXPECTED_META_LANG != req.header['datadog-meta-lang'][0]
        e = "bad meta lang #{req.header['datadog-meta-lang']}"
        puts e
        raise e
      end
      if EXPECTED_META_LANG_VERSION != req.header['datadog-meta-lang-version'][0]
        e = "bad meta lang version #{req.header['datadog-meta-lang-version']}"
        puts e
        raise e
      end
      if EXPECTED_META_LANG_INTEPRETER != req.header['datadog-meta-lang-interpreter'][0]
        e = "bad meta lang interpreter #{req.header['datadog-meta-lang-interpreter']}"
        puts e
        raise e
      end
      if EXPECTED_META_TRACER_VERSION != req.header['datadog-meta-tracer-version'][0]
        e = "bad meta tracer version #{req.header['datadog-meta-tracer-version']}"
        puts e
        raise e
      end
    end
  end

  def test_agent_receives_span
    @thread = Thread.new { @server.start }

    tracer = Datadog::Tracer.new
    tracer.configure(enabled: true, hostname: '127.0.0.1', port: TEST_PORT)

    tracer.trace('op1') do |span|
      span.service = 'my.service'
      sleep(0.001)
    end

    tracer.trace('op2') do |span|
      span.service = 'my.service'
      tracer.trace('op3') do
        true
      end
    end

    # timeout after 3 seconds, waiting for 1 flush
    test_repeat.times do
      break if tracer.writer.stats[:traces_flushed] >= 2
      sleep(0.1)
    end

    stats = tracer.writer.stats
    assert_equal(2, stats[:traces_flushed], 'wrong number of traces flushed')
    assert_equal(0, stats[:transport][:client_error])
    assert_equal(0, stats[:transport][:server_error])
    assert_equal(0, stats[:transport][:internal_error])
  ensure
    @server.shutdown
  end
end
