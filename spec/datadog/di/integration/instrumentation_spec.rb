require "datadog/di/spec_helper"
require 'datadog/di'

# Note: this file contains integration tests for instrumentation.
# This level of testing requires using ProbeManager in addition to Instrumenter.
# For Instrumenter-only tests, use instrumenter_spec.rb in the parent
# directory.

# rubocop:disable Style/RescueModifier

class InstrumentationSpecTestClass
  def test_method(a = 1)
    42
  end

  def mutating_method(greeting)
    greeting.sub!('hello', 'bye')
  end
end

RSpec.describe 'Instrumentation integration' do
  di_test

  after do
    component.shutdown!
  end

  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |settings|
      settings.remote.enabled = true
      settings.dynamic_instrumentation.enabled = true
      settings.dynamic_instrumentation.internal.development = true
      settings.dynamic_instrumentation.internal.propagate_all_exceptions = true
    end
  end

  let(:instrumenter) do
    component.instrumenter
  end

  let(:probe_manager) do
    component.probe_manager
  end

  let(:agent_settings) do
    double('agent settings')
  end

  let(:component) do
    Datadog::DI::Component.build!(settings, agent_settings)
  end

  let(:expected_installed_payload) do
    {ddsource: 'dd_debugger',
     debugger: {
       diagnostics: {
         parentId: nil,
         probeId: String,
         probeVersion: 0,
         runtimeId: String,
         status: 'INSTALLED',
       }
     },
     message: String,
     service: 'rspec',
     timestamp: Integer,}
  end

  let(:expected_emitting_payload) do
    {ddsource: 'dd_debugger',
     debugger: {
       diagnostics: {
         parentId: nil,
         probeId: String,
         probeVersion: 0,
         runtimeId: String,
         status: 'EMITTING',
       }
     },
     message: String,
     service: 'rspec',
     timestamp: Integer,}
  end

  context 'log probe' do
    before do
      allow(agent_settings).to receive(:hostname)
      allow(agent_settings).to receive(:port)
      allow(agent_settings).to receive(:timeout_seconds).and_return(1)
      allow(agent_settings).to receive(:ssl)

      allow(Datadog::DI).to receive(:component).and_return(component)
    end

    context 'method probe' do
      context 'basic probe' do
        let(:probe) do
          Datadog::DI::Probe.new(id: "1234", type: :log,
            type_name: 'InstrumentationSpecTestClass', method_name: 'test_method',
            capture_snapshot: false,)
        end

        it 'invokes probe' do
          expect(component.transport).to receive(:send_request).at_least(:once)
          probe_manager.add_probe(probe)
          expect(component.probe_notifier_worker).to receive(:add_snapshot).once.and_call_original
          expect(InstrumentationSpecTestClass.new.test_method).to eq(42)
          component.probe_notifier_worker.flush
        end

        def run_test
          expect(component.transport).to receive(:send_request).at_least(:once)
          probe_manager.add_probe(probe)
          payload = nil
          expect(component.probe_notifier_worker).to receive(:add_snapshot) do |payload_|
            payload = payload_
          end

          yield

          component.probe_notifier_worker.flush

          expect(payload).to be_a(Hash)
          snapshot = payload.fetch(:"debugger.snapshot")
          expect(snapshot[:captures]).to be nil
        end

        it 'assembles expected notification payload which does not include captures' do
          run_test do
            expect(InstrumentationSpecTestClass.new.test_method).to eq(42)
          end
        end

        context 'when method is defined after probe is added to probe manager' do
          let(:probe) do
            Datadog::DI::Probe.new(id: "1234", type: :log,
              type_name: 'InstrumentationDelayedTestClass', method_name: 'test_method',
              capture_snapshot: false,)
          end

          it 'invokes probe and creates expected snapshot' do
            expect(component.transport).to receive(:send_request).at_least(:once)
            expect(probe_manager.add_probe(probe)).to be false

            class InstrumentationDelayedTestClass # rubocop:disable Lint/ConstantDefinitionInBlock
              def test_method
                43
              end
            end

            payload = nil
            expect(component.probe_notifier_worker).to receive(:add_snapshot) do |payload_|
              payload = payload_
            end

            expect(InstrumentationDelayedTestClass.new.test_method).to eq(43)
            component.probe_notifier_worker.flush

            snapshot = payload.fetch(:"debugger.snapshot")
            expect(snapshot).to match(
              id: String,
              timestamp: Integer,
              evaluationErrors: [],
              probe: {id: '1234', version: 0, location: {
                method: 'test_method', type: 'InstrumentationDelayedTestClass',
              }},
              language: 'ruby',
              stack: Array,
              captures: nil,
            )
          end
        end
      end

      context 'enriched probe' do
        let(:probe) do
          Datadog::DI::Probe.new(id: "1234", type: :log,
            type_name: 'InstrumentationSpecTestClass', method_name: 'test_method',
            capture_snapshot: true,)
        end

        let(:expected_captures) do
          {entry: {arguments: {}, throwable: nil},
           return: {arguments: {"@return": {type: 'Integer', value: '42'}}, throwable: nil},}
        end

        it 'invokes probe' do
          expect(component.transport).to receive(:send_request).at_least(:once)
          probe_manager.add_probe(probe)
          expect(component.probe_notifier_worker).to receive(:add_snapshot).once.and_call_original
          expect(InstrumentationSpecTestClass.new.test_method).to eq(42)
          component.probe_notifier_worker.flush
        end

        def run_test
          expect(component.transport).to receive(:send_request).at_least(:once)
          probe_manager.add_probe(probe)
          payload = nil
          expect(component.probe_notifier_worker).to receive(:add_snapshot) do |payload_|
            payload = payload_
          end

          yield

          component.probe_notifier_worker.flush

          expect(payload).to be_a(Hash)
          captures = payload.fetch(:"debugger.snapshot").fetch(:captures)
          expect(captures).to eq(expected_captures)
        end

        it 'assembles expected notification payload' do
          run_test do
            expect(InstrumentationSpecTestClass.new.test_method).to eq(42)
          end
        end

        context 'when argument is mutated by method' do
          let(:probe) do
            Datadog::DI::Probe.new(id: "1234", type: :log,
              type_name: 'InstrumentationSpecTestClass', method_name: 'mutating_method',
              capture_snapshot: true,)
          end

          let(:expected_captures) do
            {entry: {arguments: {
              arg1: {type: 'String', value: 'hello world'},
            }, throwable: nil},
             return: {arguments: {
               "@return": {type: 'String', value: 'bye world'},
             }, throwable: nil},}
          end

          it 'captures original argument value at entry' do
            run_test do
              expect(InstrumentationSpecTestClass.new.mutating_method('hello world')).to eq('bye world')
            end
          end
        end
      end

      context 'when target is invoked' do
        let(:probe) do
          Datadog::DI::Probe.new(id: "1234", type: :log,
            type_name: 'InstrumentationSpecTestClass', method_name: 'test_method')
        end

        it 'notifies agent that probe is emitting' do
          expect(component.probe_notifier_worker).to receive(:add_status) do |status|
            expect(status).to match(expected_installed_payload)
          end
          probe_manager.add_probe(probe)
          expect(component.probe_notifier_worker).to receive(:add_status) do |status|
            expect(status).to match(expected_emitting_payload)
          end
          allow(component.probe_notifier_worker).to receive(:add_snapshot)
          expect(InstrumentationSpecTestClass.new.test_method).to eq(42)
          component.probe_notifier_worker.flush
        end

        context 'when target is invoked multiple times' do
          it 'notifies that probe is emitting only once at first invocation' do
            expect(component.probe_notifier_worker).to receive(:add_status) do |status|
              expect(status).to match(expected_installed_payload)
            end
            probe_manager.add_probe(probe)

            expect(component.probe_notifier_worker).to receive(:add_status) do |status|
              expect(status).to match(expected_emitting_payload)
            end
            expect(component.probe_notifier_worker).to receive(:add_snapshot)
            expect(InstrumentationSpecTestClass.new.test_method).to eq(42)
            component.probe_notifier_worker.flush

            expect(component.probe_notifier_worker).not_to receive(:add_status)
            expect(component.probe_notifier_worker).to receive(:add_snapshot)
            expect(InstrumentationSpecTestClass.new.test_method).to eq(42)
            component.probe_notifier_worker.flush
          end
        end
      end
    end

    context 'line probe' do
      with_code_tracking

      context 'simple log probe' do
        let(:probe) do
          Datadog::DI::Probe.new(id: "1234", type: :log,
            file: 'instrumentation_integration_test_class.rb', line_no: 10,
            capture_snapshot: false,)
        end

        before do
          Object.send(:remove_const, :InstrumentationIntegrationTestClass) rescue nil
          load File.join(File.dirname(__FILE__), 'instrumentation_integration_test_class.rb')
        end

        shared_examples 'simple log probe' do
          it 'invokes probe' do
            expect(component.transport).to receive(:send_request).at_least(:once)
            probe_manager.add_probe(probe)
            component.probe_notifier_worker.flush
            expect(probe_manager.installed_probes.length).to eq 1
            expect(component.probe_notifier_worker).to receive(:add_snapshot).once.and_call_original
            expect(InstrumentationIntegrationTestClass.new.test_method).to eq(42)
          end

          describe 'payload' do
            let(:payload) do
              probe_manager.add_probe(probe)
              payload = nil
              expect(component.probe_notifier_worker).to receive(:add_snapshot) do |payload_|
                payload = payload_
              end
              expect(InstrumentationIntegrationTestClass.new.test_method).to eq(42)
              component.probe_notifier_worker.flush
              expect(payload).to be_a(Hash)
              payload
            end

            let(:snapshot) do
              payload.fetch(:"debugger.snapshot")
            end

            it 'does not have captures' do
              expect(component.transport).to receive(:send_request).at_least(:once)
              expect(snapshot.fetch(:captures)).to be nil
            end

            let(:stack) do
              snapshot.fetch(:stack)
            end

            let(:top_stack_frame) do
              stack.first
            end

            it 'has instrumented location as top stack frame' do
              expect(component.transport).to receive(:send_request).at_least(:once)
              expect(File.basename(top_stack_frame.fetch(:fileName))).to eq 'instrumentation_integration_test_class.rb'
            end
          end
        end

        include_examples 'simple log probe'

        context 'target line is the end line of a method' do
          let(:probe) do
            Datadog::DI::Probe.new(id: "1234", type: :log,
              file: 'instrumentation_integration_test_class.rb', line_no: 11,
              capture_snapshot: false,)
          end

          include_examples 'simple log probe'
        end

        context 'target line is the end line of a block' do
          let(:probe) do
            Datadog::DI::Probe.new(id: "1234", type: :log,
              file: 'instrumentation_integration_test_class.rb', line_no: 17,
              capture_snapshot: false,)
          end

          it 'invokes probe' do
            expect(component.transport).to receive(:send_request).at_least(:once)
            probe_manager.add_probe(probe)
            component.probe_notifier_worker.flush
            expect(probe_manager.installed_probes.length).to eq 1
            expect(component.probe_notifier_worker).to receive(:add_snapshot).once.and_call_original
            expect(InstrumentationIntegrationTestClass.new.test_method_with_block).to eq([1])
          end

          describe 'payload' do
            let(:payload) do
              probe_manager.add_probe(probe)
              payload = nil
              expect(component.probe_notifier_worker).to receive(:add_snapshot) do |payload_|
                payload = payload_
              end
              expect(InstrumentationIntegrationTestClass.new.test_method_with_block).to eq([1])
              component.probe_notifier_worker.flush
              expect(payload).to be_a(Hash)
              payload
            end

            let(:snapshot) do
              payload.fetch(:"debugger.snapshot")
            end

            it 'does not have captures' do
              expect(component.transport).to receive(:send_request).at_least(:once)
              expect(snapshot.fetch(:captures)).to be nil
            end

            let(:stack) do
              snapshot.fetch(:stack)
            end

            let(:top_stack_frame) do
              stack.first
            end

            it 'has instrumented location as top stack frame' do
              expect(component.transport).to receive(:send_request).at_least(:once)
              expect(File.basename(top_stack_frame.fetch(:fileName))).to eq 'instrumentation_integration_test_class.rb'
            end
          end
        end

        shared_examples 'installs but does not invoke probe' do
          it 'installs but does not invoke probe' do
            expect(component.transport).to receive(:send_request).once
            probe_manager.add_probe(probe)
            component.probe_notifier_worker.flush
            expect(probe_manager.installed_probes.length).to eq 1
            expect(component.probe_notifier_worker).not_to receive(:add_snapshot)
            call_target
          end
        end

        context 'target line is else of a conditional' do
          let(:probe) do
            Datadog::DI::Probe.new(id: "1234", type: :log,
              file: 'instrumentation_integration_test_class.rb', line_no: 23,
              capture_snapshot: false,)
          end

          let(:call_target) do
            expect(InstrumentationIntegrationTestClass.new.test_method_with_conditional).to eq(2)
          end

          include_examples 'installs but does not invoke probe'
        end

        context 'target line is end of a conditional' do
          let(:probe) do
            Datadog::DI::Probe.new(id: "1234", type: :log,
              file: 'instrumentation_integration_test_class.rb', line_no: 25,
              capture_snapshot: false,)
          end

          let(:call_target) do
            expect(InstrumentationIntegrationTestClass.new.test_method_with_conditional).to eq(2)
          end

          include_examples 'installs but does not invoke probe'
        end

        context 'target line contains a comment (no executable code)' do
          let(:probe) do
            Datadog::DI::Probe.new(id: "1234", type: :log,
              file: 'instrumentation_integration_test_class.rb', line_no: 31,
              capture_snapshot: false,)
          end

          # We currently are not told that the line is not executable.
          it 'installs probe' do
            expect(probe_manager.add_probe(probe)).to be true
            expect(probe_manager.installed_probes.length).to eq 1
          end
        end
      end

      context 'enriched probe' do
        let(:probe) do
          Datadog::DI::Probe.new(id: "1234", type: :log,
            file: 'instrumentation_integration_test_class.rb', line_no: 10,
            capture_snapshot: true,)
        end

        let(:expected_captures) do
          {lines: {10 => {locals: {
            a: {type: 'Integer', value: '21'},
            password: {type: 'String', notCapturedReason: 'redactedIdent'},
            redacted: {type: 'Hash', entries: [
              [{type: 'Symbol', value: 'b'}, {type: 'Integer', value: '33'}],
              [{type: 'Symbol', value: 'session'}, {type: 'String', notCapturedReason: 'redactedIdent'}],
            ]},
          }}}}
        end

        before do
          Object.send(:remove_const, :InstrumentationIntegrationTestClass) rescue nil
          load File.join(File.dirname(__FILE__), 'instrumentation_integration_test_class.rb')
        end

        it 'invokes probe' do
          expect(component.transport).to receive(:send_request).at_least(:once)
          probe_manager.add_probe(probe)
          expect(component.probe_notifier_worker).to receive(:add_snapshot).once.and_call_original
          expect(InstrumentationIntegrationTestClass.new.test_method).to eq(42)
          component.probe_notifier_worker.flush
        end

        it 'assembles expected notification payload' do
          expect(component.transport).to receive(:send_request).at_least(:once)
          probe_manager.add_probe(probe)
          payload = nil
          expect(component.probe_notifier_worker).to receive(:add_snapshot) do |payload_|
            payload = payload_
          end
          expect(InstrumentationIntegrationTestClass.new.test_method).to eq(42)
          component.probe_notifier_worker.flush

          expect(payload).to be_a(Hash)
          captures = payload.fetch(:"debugger.snapshot").fetch(:captures)
          expect(captures).to eq(expected_captures)
        end
      end

      context 'when target file is not loaded initially and is loaded later' do
        context 'when code tracking is available' do
          with_code_tracking

          let(:probe) do
            Datadog::DI::Probe.new(id: "1234", type: :log,
              file: 'instrumentation_integration_test_class_2.rb', line_no: 10,)
          end

          it 'instruments file when it is loaded' do
            probe_manager.add_probe(probe)

            expect(probe_manager.pending_probes.length).to eq 1
            expect(probe_manager.installed_probes.length).to eq 0

            expect(component.probe_notification_builder).to receive(:build_installed).and_call_original
            expect(component.transport).to receive(:send_request).at_least(:once)

            require_relative 'instrumentation_integration_test_class_2'

            expect(probe_manager.pending_probes.length).to eq 0
            expect(probe_manager.installed_probes.length).to eq 1

            expect(component.probe_notification_builder).to receive(:build_executed).and_call_original

            InstrumentationIntegrationTestClass2.new.test_method

            component.probe_notifier_worker.flush
          end
        end

        context 'when code tracking is not available' do
          without_code_tracking

          context 'untargeted trace points enabled' do
            let(:probe) do
              Datadog::DI::Probe.new(id: "1234", type: :log,
                file: 'instrumentation_integration_test_class_3.rb', line_no: 10,)
            end

            before do
              settings.dynamic_instrumentation.internal.untargeted_trace_points = true
            end

            after do
              settings.dynamic_instrumentation.internal.untargeted_trace_points = false
            end

            it 'instruments file immediately' do
              expect(component.transport).to receive(:send_request).at_least(:once)

              probe_manager.add_probe(probe)

              expect(probe_manager.pending_probes.length).to eq 0
              expect(probe_manager.installed_probes.length).to eq 1

              # This require does not change instrumentation
              require_relative 'instrumentation_integration_test_class_3'

              expect(probe_manager.pending_probes.length).to eq 0
              expect(probe_manager.installed_probes.length).to eq 1

              expect(component.probe_notification_builder).to receive(:build_executed).and_call_original

              InstrumentationIntegrationTestClass3.new.test_method

              component.probe_notifier_worker.flush
            end
          end

          context 'untargeted trace points disabled' do
            let(:probe) do
              Datadog::DI::Probe.new(id: "1234", type: :log,
                file: 'instrumentation_integration_test_class_4.rb', line_no: 10,)
            end

            before do
              settings.dynamic_instrumentation.internal.untargeted_trace_points = false
            end

            it 'does not instrument file when it is loaded' do
              probe_manager.add_probe(probe)

              expect(probe_manager.pending_probes.length).to eq 1
              expect(probe_manager.installed_probes.length).to eq 0

              require_relative 'instrumentation_integration_test_class_4'

              expect(probe_manager.pending_probes.length).to eq 1
              expect(probe_manager.installed_probes.length).to eq 0

              expect(component.probe_notification_builder).not_to receive(:build_executed).and_call_original

              InstrumentationIntegrationTestClass4.new.test_method

              component.probe_notifier_worker.flush
            end
          end
        end
      end

      context 'when target is invoked' do
        before do
          Object.send(:remove_const, :InstrumentationIntegrationTestClass) rescue nil
          load File.join(File.dirname(__FILE__), 'instrumentation_integration_test_class.rb')
        end

        let(:probe) do
          Datadog::DI::Probe.new(id: "1234", type: :log,
            file: 'instrumentation_integration_test_class.rb', line_no: 10,
            capture_snapshot: false,)
        end

        it 'notifies agent that probe is emitting' do
          expect(component.probe_notifier_worker).to receive(:add_status) do |status|
            expect(status).to match(expected_installed_payload)
          end
          expect(probe_manager.add_probe(probe)).to be true

          expect(component.probe_notifier_worker).to receive(:add_status) do |status|
            expect(status).to match(expected_emitting_payload)
          end
          allow(component.probe_notifier_worker).to receive(:add_snapshot)
          expect(InstrumentationIntegrationTestClass.new.test_method).to eq(42)
          component.probe_notifier_worker.flush
        end

        context 'when target is invoked multiple times' do
          it 'notifies that probe is emitting only once at first invocation' do
            expect(component.probe_notifier_worker).to receive(:add_status) do |status|
              expect(status).to match(expected_installed_payload)
            end
            expect(probe_manager.add_probe(probe)).to be true

            expect(component.probe_notifier_worker).to receive(:add_status) do |status|
              expect(status).to match(expected_emitting_payload)
            end
            expect(component.probe_notifier_worker).to receive(:add_snapshot)
            expect(InstrumentationIntegrationTestClass.new.test_method).to eq(42)
            component.probe_notifier_worker.flush

            expect(component.probe_notifier_worker).not_to receive(:add_status)
            expect(component.probe_notifier_worker).to receive(:add_snapshot)
            expect(InstrumentationIntegrationTestClass.new.test_method).to eq(42)
            component.probe_notifier_worker.flush
          end
        end
      end
    end
  end
end

# rubocop:enable Style/RescueModifier
