# frozen_string_literal: true

require 'datadog/core'

RSpec.describe 'Datadog::Tracing::Transport::Native::TraceExporter' do
  before do
    skip_if_libdatadog_not_supported
  end

  let(:native_module) { Datadog::Tracing::Transport::Native }
  let(:trace_exporter_class) { native_module::TraceExporter }

  describe '._native_new' do
    context 'with all string arguments' do
      it 'creates an exporter' do
        exporter = trace_exporter_class._native_new(
          url: 'http://127.0.0.1:8126',
          tracer_version: '1.0.0',
          language: 'ruby',
          language_version: RUBY_VERSION,
          language_interpreter: RUBY_ENGINE,
          hostname: 'testhost',
          env: 'test',
          service: 'testsvc',
          version: '1.0',
        )
        expect(exporter).to be_a(trace_exporter_class)
      end
    end

    context 'with nil for all optional arguments' do
      it 'creates an exporter' do
        exporter = trace_exporter_class._native_new(
          url: 'http://127.0.0.1:8126',
          tracer_version: nil, language: nil, language_version: nil,
          language_interpreter: nil, hostname: nil, env: nil,
          service: nil, version: nil,
        )
        expect(exporter).to be_a(trace_exporter_class)
      end
    end

    context 'with a non-string url' do
      it 'raises TypeError' do
        expect {
          trace_exporter_class._native_new(
            url: 12345,
            tracer_version: nil, language: nil, language_version: nil,
            language_interpreter: nil, hostname: nil, env: nil,
            service: nil, version: nil,
          )
        }.to raise_error(TypeError)
      end
    end

    context 'with a non-string optional argument' do
      it 'raises TypeError' do
        expect {
          trace_exporter_class._native_new(
            url: 'http://127.0.0.1:8126',
            tracer_version: 123, # should be String or nil
            language: nil, language_version: nil,
            language_interpreter: nil, hostname: nil, env: nil,
            service: nil, version: nil,
          )
        }.to raise_error(TypeError)
      end
    end

    it 'cannot be allocated directly' do
      expect { trace_exporter_class.new }.to raise_error(TypeError)
    end

    context 'GC safety' do
      it 'does not crash when instances are garbage collected' do
        5.times do
          trace_exporter_class._native_new(
            url: 'http://127.0.0.1:8126',
            tracer_version: nil, language: nil, language_version: nil,
            language_interpreter: nil, hostname: nil, env: nil,
            service: nil, version: nil,
          )
        end
        GC.start
        GC.start
      end
    end
  end
end
