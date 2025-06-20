require "datadog/di/spec_helper"
require 'datadog/di/serializer'
require 'datadog/di/probe'
require 'datadog/di/probe_notification_builder'

RSpec.describe Datadog::DI::ProbeNotificationBuilder do
  di_test

  describe 'log probe' do
    let(:redactor) { Datadog::DI::Redactor.new(settings) }
    let(:serializer) { Datadog::DI::Serializer.new(settings, redactor) }

    let(:builder) { described_class.new(settings, serializer) }

    let(:instrumenter) do
      Datadog::DI::Instrumenter.new(settings)
    end

    let(:settings) do
      double('settings').tap do |settings|
        allow(settings).to receive(:dynamic_instrumentation).and_return(di_settings)
        allow(settings).to receive(:service).and_return('fake service')
        allow(settings).to receive(:env).and_return('fake env')
        allow(settings).to receive(:version).and_return('fake version')
        allow(settings).to receive(:tags).and_return({})
      end
    end

    let(:di_settings) do
      double('di settings').tap do |settings|
        allow(settings).to receive(:enabled).and_return(true)
        allow(settings).to receive(:untargeted_trace_points).and_return(false)
        allow(settings).to receive(:max_capture_depth).and_return(2)
        allow(settings).to receive(:max_capture_attribute_count).and_return(2)
        allow(settings).to receive(:max_capture_string_length).and_return(20)
        allow(settings).to receive(:max_capture_collection_size).and_return(20)
        allow(settings).to receive(:redacted_type_names).and_return([])
        allow(settings).to receive(:redacted_identifiers).and_return([])
      end
    end

    context 'line probe' do
      let(:probe) do
        Datadog::DI::Probe.new(id: '123', type: :log, file: 'X', line_no: 1, capture_snapshot: true)
      end

      context 'with snapshot' do
        let(:locals) do
          double('local variables').tap do |locals|
            # Adding instance variables to the locals
            expect(locals).to receive(:merge).and_return(locals)
          end
        end

        let(:captures) do
          {lines: {1 => {
            locals: locals,
          }}}
        end

        it 'builds expected payload' do
          payload = builder.build_snapshot(probe, locals: locals)
          expect(payload).to be_a(Hash)
          expect(payload.fetch(:"debugger.snapshot").fetch(:captures)).to eq(captures)
        end
      end
    end

    context 'method probe' do
      let(:probe) do
        Datadog::DI::Probe.new(id: '123', type: :log, type_name: 'X', method_name: 'y', capture_snapshot: true)
      end

      context 'with snapshot' do
        let(:args) do
          [1, 'hello']
        end

        let(:kwargs) do
          {foo: 42}
        end

        let(:instance_vars) do
          {"@ivar": 42}
        end

        let(:expected_captures) do
          {entry: {
            arguments: {
              arg1: {type: 'Integer', value: '1'},
              arg2: {type: 'String', value: 'hello'},
              foo: {type: 'Integer', value: '42'},
              "@ivar": {type: 'Integer', value: '42'},
            }, throwable: nil,
          }, return: {
            arguments: {
              :"@ivar" => {type: 'Integer', value: '42'},
              :@return => {
                type: 'NilClass',
                isNull: true,
              },
            }, throwable: nil,
          }}
        end

        it 'builds expected payload' do
          payload = builder.build_snapshot(probe, args: args, kwargs: kwargs, instance_vars: instance_vars)
          expect(payload).to be_a(Hash)
          captures = payload.fetch(:"debugger.snapshot").fetch(:captures)
          expect(captures).to eq(expected_captures)
        end
      end
    end
  end
end
