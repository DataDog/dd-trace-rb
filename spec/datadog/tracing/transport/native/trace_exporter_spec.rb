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
          'http://127.0.0.1:8126',
          '1.0.0',      # tracer_version
          'ruby',       # language
          RUBY_VERSION, # language_version
          RUBY_ENGINE,  # language_interpreter
          'testhost',   # hostname
          'test',       # env
          'testsvc',    # service
          '1.0',        # version
        )
        expect(exporter).to be_a(trace_exporter_class)
      end
    end

    context 'with nil for all optional arguments' do
      it 'creates an exporter' do
        exporter = trace_exporter_class._native_new(
          'http://127.0.0.1:8126',
          nil, nil, nil, nil, nil, nil, nil, nil,
        )
        expect(exporter).to be_a(trace_exporter_class)
      end
    end

    context 'with a non-string url' do
      it 'raises TypeError' do
        expect {
          trace_exporter_class._native_new(
            12345, nil, nil, nil, nil, nil, nil, nil, nil,
          )
        }.to raise_error(TypeError)
      end
    end

    context 'with a non-string optional argument' do
      it 'raises TypeError' do
        expect {
          trace_exporter_class._native_new(
            'http://127.0.0.1:8126',
            123, # tracer_version should be String or nil
            nil, nil, nil, nil, nil, nil, nil,
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
            'http://127.0.0.1:8126',
            nil, nil, nil, nil, nil, nil, nil, nil,
          )
        end
        GC.start
        GC.start
      end
    end
  end
end
