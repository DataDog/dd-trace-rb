require 'helper'
require 'ddtrace'
require 'ddtrace/tracer'
require 'thread'
require 'webrick'

class TraceCountHeaderTest < Minitest::Test
  TEST_PORT = 6218

  def setup
    @server = WEBrick::HTTPServer.new Port: TEST_PORT

    @server.mount_proc '/' do |req, res|
      res.body = '{}'
      trace_count = req.header['x-datadog-trace-count']
      if trace_count.nil? || trace_count.empty? || trace_count[0].to_i < 1 || trace_count[0].to_i > 2
        raise "bad trace count header: #{trace_count}"
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
