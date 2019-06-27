require 'spec_helper'

require 'ddtrace'
require 'ddtrace/tracer'
require 'stringio'
require 'thread'
require 'webrick'

RSpec.describe 'Meta headers' do
  before(:each) do
    server.mount_proc('/', &server_proc)
    Thread.new { server.start }
  end
  after(:each) { server.shutdown }

  let(:server) { WEBrick::HTTPServer.new(Port: port, Logger: log, AccessLog: access_log) }
  let(:port) { 6219 }
  let(:log) { WEBrick::Log.new(log_buffer) }
  let(:log_buffer) { StringIO.new }
  let(:access_log) { [[log_buffer, WEBrick::AccessLog::COMBINED_LOG_FORMAT]] }
  let(:server_proc) do
    proc do |req, res|
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

      if meta_lang != req.header['datadog-meta-lang'][0]
        e = "bad meta lang #{req.header['datadog-meta-lang']}"
        puts e
        raise e
      end
      if meta_lang_version != req.header['datadog-meta-lang-version'][0]
        e = "bad meta lang version #{req.header['datadog-meta-lang-version']}"
        puts e
        raise e
      end
      if meta_lang_interpreter != req.header['datadog-meta-lang-interpreter'][0]
        e = "bad meta lang interpreter #{req.header['datadog-meta-lang-interpreter']}"
        puts e
        raise e
      end
      if meta_lang_tracer_version != req.header['datadog-meta-tracer-version'][0]
        e = "bad meta tracer version #{req.header['datadog-meta-tracer-version']}"
        puts e
        raise e
      end
    end
  end

  let(:meta_lang) { Datadog::Ext::Runtime::LANG }
  let(:meta_lang_version) { Datadog::Ext::Runtime::LANG_VERSION }
  let(:meta_lang_interpreter) { Datadog::Ext::Runtime::LANG_INTERPRETER }
  let(:meta_lang_tracer_version) { Datadog::Ext::Runtime::TRACER_VERSION }

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
