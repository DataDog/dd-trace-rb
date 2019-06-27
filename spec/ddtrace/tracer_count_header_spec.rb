require 'spec_helper'

require 'ddtrace'
require 'ddtrace/tracer'
require 'stringio'
require 'thread'
require 'webrick'

RSpec.describe 'Trace count header' do
  before(:each) do
    server.mount_proc('/', &server_proc)
    Thread.new { server.start }
  end
  after(:each) { server.shutdown }

  let(:server) { WEBrick::HTTPServer.new(Port: port, Logger: log, AccessLog: access_log) }
  let(:port) { 6218 }
  let(:log) { WEBrick::Log.new(log_buffer) }
  let(:log_buffer) { StringIO.new }
  let(:access_log) { [[log_buffer, WEBrick::AccessLog::COMBINED_LOG_FORMAT]] }
  let(:server_proc) do
    proc do |req, res|
      res.body = '{}'
      trace_count = req.header['x-datadog-trace-count']
      if trace_count.nil? || trace_count.empty? || trace_count[0].to_i < 1 || trace_count[0].to_i > 2
        raise "bad trace count header: #{trace_count}"
      end
    end
  end

  before(:each) { tracer.configure(enabled: true, hostname: '127.0.0.1', port: port) }
  let(:tracer) { Datadog::Tracer.new }

  context 'when traces are sent' do
    before(:each) do
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

      # Timeout after 3 seconds, waiting for 1 flush
      test_repeat.times do
        break if tracer.writer.stats[:traces_flushed] >= 2
        sleep(0.1)
      end
    end

    let(:stats) { tracer.writer.stats }

    it 'flushes the correct number of traces' do
      expect(stats[:traces_flushed]).to eq(2)
      expect(stats[:transport].client_error).to eq(0)
      expect(stats[:transport].server_error).to eq(0)
      expect(stats[:transport].internal_error).to eq(0)
    end
  end
end
