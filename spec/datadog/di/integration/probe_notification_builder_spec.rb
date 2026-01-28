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
        allow(settings).to receive(:experimental_propagate_process_tags_enabled).and_return(false)
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
        allow(settings).to receive(:redaction_excluded_identifiers).and_return([])
      end
    end

    context 'line probe' do
      let(:probe) do
        Datadog::DI::Probe.new(
          id: '123', type: :log, file: 'X', line_no: 1,
          capture_snapshot: true
        )
      end

      context 'with snapshot' do
        let(:locals) do
          {local: 'var'}
        end

        let(:captures) do
          {lines: {1 => {
            locals: {local: {type: 'String', value: 'var'}},
            arguments: {self: {
              type: 'Object',
              fields: {},
            }},
          }}}
        end

        let(:context) do
          Datadog::DI::Context.new(
            settings: settings, serializer: serializer,
            probe: probe, locals: locals, target_self: Object.new
          )
        end

        it 'builds expected payload' do
          payload = builder.build_snapshot(context)
          expect(payload).to be_a(Hash)
          expect(payload.fetch(:debugger).fetch(:snapshot).fetch(:captures)).to eq(captures)
        end
      end
    end

    context 'method probe' do
      let(:probe) do
        Datadog::DI::Probe.new(id: '123', type: :log, type_name: 'X', method_name: 'y', capture_snapshot: true)
      end

      context 'with snapshot' do
        let(:serialized_entry_args) do
          {
            arg1: {type: 'Integer', value: '1'},
            arg2: {type: 'String', value: 'hello'},
            foo: {type: 'Integer', value: '42'},
            self: {type: 'Object', fields: {}},
          }
        end

        let(:expected_captures) do
          {entry: {
            arguments: {
              arg1: {type: 'Integer', value: '1'},
              arg2: {type: 'String', value: 'hello'},
              foo: {type: 'Integer', value: '42'},
              self: {type: 'Object', fields: {}},
            },
          }, return: {
            arguments: {
              :self => {
                type: 'Object',
                fields: {},
              },
              :@return => {
                type: 'NilClass',
                isNull: true,
              },
            }, throwable: nil,
          }}
        end

        let(:context) do
          Datadog::DI::Context.new(
            settings: settings, serializer: serializer,
            probe: probe, serialized_entry_args: serialized_entry_args,
            target_self: Object.new
          )
        end

        it 'builds expected payload' do
          payload = builder.build_snapshot(context)
          expect(payload).to be_a(Hash)
          captures = payload.fetch(:debugger).fetch(:snapshot).fetch(:captures)
          expect(captures).to eq(expected_captures)
        end
      end

      context 'with template segments' do
        let(:probe_spec) do
          {id: '11', name: 'bar', type: 'LOG_PROBE', where: {
                                                       typeName: 'Foo', methodName: 'bar'
                                                     },
           segments: segments}
        end

        let(:segments) do
          [
            {str: 'hello'},
            {json: {ref: 'bar'}, dsl: '(expression)'},
          ]
        end

        let(:probe) do
          Datadog::DI::ProbeBuilder.build_from_remote_config(JSON.parse(probe_spec.to_json))
        end

        let(:context) do
          Datadog::DI::Context.new(
            settings: settings, serializer: serializer,
            probe: probe,
            target_self: Object.new,
            locals: {
              bar: 42,
            },
          )
        end

        it 'builds expected message' do
          payload = builder.build_snapshot(context)
          expect(payload).to be_a(Hash)
          expect(payload[:message]).to eq 'hello42'

          # We asked to not create a snapshot
          expect(payload.fetch(:debugger).fetch(:snapshot).fetch(:captures)).to eq({})
        end

        context 'when there is an evaluation error' do
          let(:segments) do
            [
              {str: 'hello'},
              {json: {substring: ['bar', 'baz', 3]}, dsl: '(expression)'},
            ]
          end

          it 'replaces bogus expressions with [evaluation error] and fills out evaluation errors' do
            payload = builder.build_snapshot(context)
            expect(payload).to be_a(Hash)
            expect(payload[:message]).to eq "hello[evaluation error]"
            expect(payload.fetch(:debugger).fetch(:snapshot).fetch(:evaluationErrors)).to eq [
              {message: 'ArgumentError: bad value for range', expr: '(expression)'}
            ]

            # We asked to not create a snapshot
            expect(payload.fetch(:debugger).fetch(:snapshot).fetch(:captures)).to eq({})
          end
        end

        context 'when there are multiple evaluation errors' do
          let(:segments) do
            [
              {str: 'hello'},
              {json: {substring: ['bar', 'baz', 3]}, dsl: '(bar baz 3)'},
              {json: {filter: ['bar', 'baz']}, dsl: '(bar baz)'},
              {str: 'hello'},
            ]
          end

          it 'attempts to evaluate all expressions' do
            payload = builder.build_snapshot(context)
            expect(payload).to be_a(Hash)
            expect(payload[:message]).to eq "hello[evaluation error][evaluation error]hello"
            expect(payload.fetch(:debugger).fetch(:snapshot).fetch(:evaluationErrors)).to eq [
              {message: 'ArgumentError: bad value for range', expr: '(bar baz 3)'},
              {message: 'Datadog::DI::Error::ExpressionEvaluationError: Bad collection type for filter: String', expr: '(bar baz)'},
            ]

            # We asked to not create a snapshot
            expect(payload.fetch(:debugger).fetch(:snapshot).fetch(:captures)).to eq({})
          end
        end

        context 'when variables are referenced but none are passed in' do
          let(:context) do
            Datadog::DI::Context.new(
              settings: settings, serializer: serializer,
              probe: probe,
              target_self: Object.new,
            )
          end

          it 'builds message with nothing substituted for variables' do
            payload = builder.build_snapshot(context)
            expect(payload).to be_a(Hash)
            # TODO maybe this output is suboptimal but we need more
            # complexity to handle missing variable references without
            # serializing nil as empty string everywhere.
            expect(payload[:message]).to eq 'hellonil'

            # We asked to not create a snapshot
            expect(payload.fetch(:debugger).fetch(:snapshot).fetch(:captures)).to eq({})
          end
        end
      end
    end
  end
end
