require "datadog/di/spec_helper"
require 'datadog/di'

# Note: this file contains integration tests for instrumentation.
# This level of testing requires using ProbeManager in addition to Instrumenter.
# For Instrumenter-only tests, use instrumenter_spec.rb in the parent
# directory.

# rubocop:disable Style/RescueModifier

class InstrumentationSpecTestClass
  class TestException < StandardError
  end

  def initialize
    @ivar = 'start value'
  end

  def test_method(a = 1)
    42
  end

  def long_test_method
    # This method is used to assert on @duration, and +test_method+
    # somehow managed to report an execution time of 0.0 in CI one time
    # (though normally it takes about 1 microsecond).
    Object.methods.length > 0 and 42
  end

  def mutating_method(greeting)
    greeting.sub!('hello', 'bye')
  end

  def ivar_mutating_method
    @ivar.sub!('start value', 'altered value')
  end

  def exception_method
    raise TestException, 'Test exception'
  end
end

RSpec.describe 'Instrumentation integration' do
  di_test

  let(:diagnostics_transport) do
    double(Datadog::DI::Transport::Diagnostics::Transport)
  end

  let(:input_transport) do
    double(Datadog::DI::Transport::Input::Transport)
  end

  before do
    # We do not have any configurations in CI that have an agent
    # implementing debugger endpoints that are used by DI transport
    # (besides system tests which use an actual agent).
    # Therefore, if we attempt to actually put payloads on the network,
    # the requests will fail.
    # Since this test enables propagation of all exceptions through DI
    # for early detection of problems, these failing requests would
    # manifest in the test suite rather than being ignored as they would be
    # in customer applications.
    allow(Datadog::DI::Transport::HTTP).to receive(:diagnostics).and_return(diagnostics_transport)
    allow(Datadog::DI::Transport::HTTP).to receive(:input).and_return(input_transport)
    allow(diagnostics_transport).to receive(:send_diagnostics)
    allow(input_transport).to receive(:send_input)
  end

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
    instance_double_agent_settings
  end

  let(:logger) do
    instance_double(Logger)
  end

  let(:component) do
    # TODO should this use Component.new? We have to manually pass in
    # the code tracker in that case.
    Datadog::DI::Component.build(settings, agent_settings, logger).tap do |component|
      if component.nil?
        raise "Component failed to create - unsuitable environment? Check log entries"
      end
    end
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
      allow(Datadog::DI).to receive(:current_component).and_return(component)
    end

    let(:agent_settings) do
      instance_double_agent_settings_with_stubs
    end

    context 'method probe' do
      context 'basic probe' do
        let(:probe) do
          Datadog::DI::Probe.new(id: "1234", type: :log,
            type_name: 'InstrumentationSpecTestClass', method_name: 'test_method',
            capture_snapshot: false,)
        end

        it 'invokes probe' do
          expect(diagnostics_transport).to receive(:send_diagnostics)
          expect(input_transport).to receive(:send_input)
          probe_manager.add_probe(probe)
          expect(component.probe_notifier_worker).to receive(:add_snapshot).once.and_call_original
          expect(InstrumentationSpecTestClass.new.test_method).to eq(42)
          component.probe_notifier_worker.flush
        end

        def run_test
          expect(diagnostics_transport).to receive(:send_diagnostics)
          # add_snapshot expectation replaces assertion on send_input
          probe_manager.add_probe(probe)
          payload = nil
          expect(component.probe_notifier_worker).to receive(:add_snapshot) do |payload_|
            payload = payload_
          end

          yield

          component.probe_notifier_worker.flush

          expect(payload).to be_a(Hash)
          expect(payload).to include(:debugger)
          snapshot = payload.fetch(:debugger).fetch(:snapshot)
          expect(snapshot.fetch(:captures)).to eq({})
        end

        it 'assembles expected notification payload which does not include captures' do
          run_test do
            expect(InstrumentationSpecTestClass.new.test_method).to eq(42)
          end
        end

        context 'when class with target method is defined after probe is added to probe manager' do
          let(:probe) do
            Datadog::DI::Probe.new(id: "1234", type: :log,
              type_name: 'InstrumentationDelayedTestClass', method_name: 'test_method',
              capture_snapshot: false,)
          end

          it 'installs probe which then is invoked and creates expected snapshot' do
            expect(diagnostics_transport).to receive(:send_diagnostics)
            # add_snapshot expectation replaces assertion on send_input
            expect(probe_manager.add_probe(probe)).to be false

            # Probe should be pending
            expect(probe_manager.pending_probes).to eq(probe.id => probe)
            expect(probe_manager.installed_probes).to be_empty

            class InstrumentationDelayedTestClass # rubocop:disable Lint/ConstantDefinitionInBlock
              def test_method
                43
              end
            end

            # Probe should now be installed, verify it was moved in the
            # accounting collections correctly.
            expect(probe_manager.pending_probes).to be_empty
            expect(probe_manager.installed_probes).to eq(probe.id => probe)

            payload = nil
            expect(component.probe_notifier_worker).to receive(:add_snapshot) do |payload_|
              payload = payload_
            end

            expect(InstrumentationDelayedTestClass.new.test_method).to eq(43)
            component.probe_notifier_worker.flush

            snapshot = payload.fetch(:debugger).fetch(:snapshot)
            expect(snapshot).to match(
              id: String,
              timestamp: Integer,
              evaluationErrors: [],
              probe: {id: '1234', version: 0, location: {
                method: 'test_method', type: 'InstrumentationDelayedTestClass',
              }},
              language: 'ruby',
              stack: Array,
              captures: {},
            )
          end

          context 'when the class is a derived class' do
            let(:probe) do
              Datadog::DI::Probe.new(id: "1234", type: :log,
                type_name: 'InstrumentationDelayedDerivedTestClass', method_name: 'test_method',
                capture_snapshot: false,)
            end

            it 'invokes probe and creates expected snapshot' do
              expect(diagnostics_transport).to receive(:send_diagnostics)
              # add_snapshot expectation replaces assertion on send_input
              expect(probe_manager.add_probe(probe)).to be false

              class InstrumentationDelayedBaseClass # rubocop:disable Lint/ConstantDefinitionInBlock
              end

              class InstrumentationDelayedDerivedTestClass < InstrumentationDelayedBaseClass # rubocop:disable Lint/ConstantDefinitionInBlock
                def test_method
                  43
                end
              end

              payload = nil
              expect(component.probe_notifier_worker).to receive(:add_snapshot) do |payload_|
                payload = payload_
              end

              expect(InstrumentationDelayedDerivedTestClass.new.test_method).to eq(43)
              component.probe_notifier_worker.flush

              snapshot = payload.fetch(:debugger).fetch(:snapshot)
              expect(snapshot).to match(
                id: String,
                timestamp: Integer,
                evaluationErrors: [],
                probe: {id: '1234', version: 0, location: {
                  method: 'test_method', type: 'InstrumentationDelayedDerivedTestClass',
                }},
                language: 'ruby',
                stack: Array,
                captures: {},
              )
            end
          end
        end

        context 'when class exists without target method and method is defined after probe is added to probe manager' do
          let(:probe) do
            Datadog::DI::Probe.new(id: "1234", type: :log,
              type_name: 'InstrumentationDelayedPartialTestClass', method_name: 'test_method',
              capture_snapshot: false,)
          end

          it 'invokes probe and creates expected snapshot' do
            class InstrumentationDelayedPartialTestClass # rubocop:disable Lint/ConstantDefinitionInBlock
              # test_method should not be defined here
            end

            expect(diagnostics_transport).to receive(:send_diagnostics)
            # add_snapshot expectation replaces assertion on send_input
            expect(probe_manager.add_probe(probe)).to be true

            class InstrumentationDelayedPartialTestClass # rubocop:disable Lint/ConstantDefinitionInBlock
              def test_method
                43
              end
            end

            payload = nil
            expect(component.probe_notifier_worker).to receive(:add_snapshot) do |payload_|
              payload = payload_
            end

            expect(InstrumentationDelayedPartialTestClass.new.test_method).to eq(43)
            component.probe_notifier_worker.flush

            snapshot = payload.fetch(:debugger).fetch(:snapshot)
            expect(snapshot).to match(
              id: String,
              timestamp: Integer,
              evaluationErrors: [],
              probe: {id: '1234', version: 0, location: {
                method: 'test_method', type: 'InstrumentationDelayedPartialTestClass',
              }},
              language: 'ruby',
              # TODO the stack trace here does not contain the target method
              # as the first frame - see the comment in Instrumenter.
              stack: Array,
              captures: {},
            )
          end
        end

        context 'when class exists and target method is virtual' do
          let(:probe) do
            Datadog::DI::Probe.new(id: "1234", type: :log,
              type_name: 'InstrumentationVirtualTestClass', method_name: 'test_method',
              capture_snapshot: false,)
          end

          it 'invokes probe and creates expected snapshot' do
            class InstrumentationVirtualTestClass # rubocop:disable Lint/ConstantDefinitionInBlock
              def method_missing(name) # rubocop:disable Style/MissingRespondToMissing
                name
              end
            end

            expect(diagnostics_transport).to receive(:send_diagnostics)
            # add_snapshot expectation replaces assertion on send_input
            expect(probe_manager.add_probe(probe)).to be true

            payload = nil
            expect(component.probe_notifier_worker).to receive(:add_snapshot) do |payload_|
              payload = payload_
            end

            expect(InstrumentationVirtualTestClass.new.test_method).to eq(:test_method)
            component.probe_notifier_worker.flush

            snapshot = payload.fetch(:debugger).fetch(:snapshot)
            expect(snapshot).to match(
              id: String,
              timestamp: Integer,
              evaluationErrors: [],
              probe: {id: '1234', version: 0, location: {
                method: 'test_method', type: 'InstrumentationVirtualTestClass',
              }},
              language: 'ruby',
              # TODO the stack trace here does not contain the target method
              # as the first frame - see the comment in Instrumenter.
              stack: Array,
              captures: {},
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
          {
            entry: {arguments: {
              self: {
                type: 'InstrumentationSpecTestClass',
                fields: {
                  "@ivar": {type: 'String', value: 'start value'},
                },
              },
            }},
            return: {arguments: {
              self: {
                type: 'InstrumentationSpecTestClass',
                fields: {
                  "@ivar": {type: 'String', value: 'start value'},
                },
              },
              "@return": {type: 'Integer', value: '42'},
            }, throwable: nil},
          }
        end

        it 'invokes probe' do
          expect(diagnostics_transport).to receive(:send_diagnostics)
          expect(input_transport).to receive(:send_input)
          probe_manager.add_probe(probe)
          expect(component.probe_notifier_worker).to receive(:add_snapshot).once.and_call_original
          expect(InstrumentationSpecTestClass.new.test_method).to eq(42)
          component.probe_notifier_worker.flush
        end

        def run_test
          expect(diagnostics_transport).to receive(:send_diagnostics)
          # add_snapshot expectation replaces assertion on send_input
          probe_manager.add_probe(probe)
          payload = nil
          expect(component.probe_notifier_worker).to receive(:add_snapshot) do |payload_|
            payload = payload_
          end

          yield

          component.probe_notifier_worker.flush

          expect(payload).to be_a(Hash)
          captures = payload.fetch(:debugger).fetch(:snapshot).fetch(:captures)
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
            {
              entry: {
                arguments: {
                  arg1: {type: 'String', value: 'hello world'},
                  self: {
                    type: 'InstrumentationSpecTestClass',
                    fields: {
                      "@ivar": {type: 'String', value: 'start value'},
                    },
                  },
                },
              },
              return: {
                arguments: {
                  self: {
                    type: 'InstrumentationSpecTestClass',
                    fields: {
                      "@ivar": {type: 'String', value: 'start value'},
                    },
                  },
                  "@return": {type: 'String', value: 'bye world'},
                },
                throwable: nil,
              },
            }
          end

          it 'captures original argument value at entry' do
            run_test do
              expect(InstrumentationSpecTestClass.new.mutating_method('hello world')).to eq('bye world')
            end
          end
        end

        context 'when instance variable is mutated by method' do
          let(:probe) do
            Datadog::DI::Probe.new(id: "1234", type: :log,
              type_name: 'InstrumentationSpecTestClass', method_name: 'ivar_mutating_method',
              capture_snapshot: true,)
          end

          let(:expected_captures) do
            {
              entry: {arguments: {
                self: {
                  type: 'InstrumentationSpecTestClass',
                  fields: {
                    "@ivar": {type: 'String', value: 'start value'},
                  },
                },
              }},
              return: {arguments: {
                self: {
                  type: 'InstrumentationSpecTestClass',
                  fields: {
                    "@ivar": {type: 'String', value: 'altered value'},
                  },
                },
                "@return": {type: 'String', value: 'altered value'},
              }, throwable: nil},
            }
          end

          it 'captures original instance variable value at entry' do
            run_test do
              expect(InstrumentationSpecTestClass.new.ivar_mutating_method).to eq('altered value')
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

      context 'when message template references special variables' do
        let(:probe) do
          Datadog::DI::ProbeBuilder.build_from_remote_config(JSON.parse(probe_spec.to_json))
        end

        let(:probe_spec) do
          {
            id: '1234',
            type: 'LOG_PROBE',
            where: {typeName: 'InstrumentationSpecTestClass', methodName: 'test_method'},
            segments: segments,
          }
        end

        context '@duration' do
          let(:segments) do
            [
              {str: 'hello '},
              {json: {ref: '@duration'}, dsl: '@duration'},
              {str: ' ms'},
            ]
          end

          let(:probe_spec) do
            {
              id: '1234',
              type: 'LOG_PROBE',
              where: {typeName: 'InstrumentationSpecTestClass', methodName: 'long_test_method'},
              segments: segments,
            }
          end

          it 'substitutes the expected value' do
            probe_manager.add_probe(probe)

            expect(component.probe_notifier_worker).to receive(:add_status) do |status|
              expect(status).to match(expected_emitting_payload)
            end
            expect(component.probe_notifier_worker).to receive(:add_snapshot) do |snapshot|
              expect(snapshot.fetch(:message)).to match(/\Ahello (\d+\.\d+) ms\z/)
              snapshot.fetch(:message) =~ /\Ahello (\d+\.\d+) ms\z/
              value = Float($1)
              # Actual execution time varies greatly in CI.
              # We had a test run where the method was reported to take
              # exactly zero seconds, and also 26 and 40 seconds.
              # The current version calls Process.clock_gettime directly
              # instead of using our helper which could invoke customer code
              # and also be mocked.
              # The reported duration in local test runs is about 0.03 seconds.
              expect(value).to be > 0
              # Set upper bound at 1000 seconds... should be safe given the
              # highest value seen so far was 40 seconds (for a method that
              # compares length of an array with an integer).
              expect(value).to be < 1000
            end
            expect(InstrumentationSpecTestClass.new.long_test_method).to eq(42)
            component.probe_notifier_worker.flush
          end
        end

        context '@return' do
          let(:segments) do
            [
              {str: 'hello '},
              {json: {ref: '@return'}, dsl: '@return'},
            ]
          end

          it 'substitutes the expected value' do
            probe_manager.add_probe(probe)

            expect(component.probe_notifier_worker).to receive(:add_status) do |status|
              expect(status).to match(expected_emitting_payload)
            end
            expect(component.probe_notifier_worker).to receive(:add_snapshot) do |snapshot|
              expect(snapshot.fetch(:message)).to eq 'hello 42'
            end
            expect(InstrumentationSpecTestClass.new.test_method).to eq(42)
            component.probe_notifier_worker.flush
          end
        end

        context '@exception' do
          let(:segments) do
            [
              {str: 'hello '},
              {json: {ref: '@exception'}, dsl: '@exception'},
            ]
          end

          context 'when method does not raise an exception' do
            it 'substitutes nil' do
              probe_manager.add_probe(probe)

              expect(component.probe_notifier_worker).to receive(:add_status) do |status|
                expect(status).to match(expected_emitting_payload)
              end
              expect(component.probe_notifier_worker).to receive(:add_snapshot) do |snapshot|
                # TODO should we serialize nil as empty string?
                expect(snapshot.fetch(:message)).to eq 'hello nil'
              end
              expect(InstrumentationSpecTestClass.new.test_method).to eq(42)
              component.probe_notifier_worker.flush
            end
          end

          context 'when method does raises an exception' do
            let(:probe_spec) do
              {
                id: '1234',
                type: 'LOG_PROBE',
                where: {typeName: 'InstrumentationSpecTestClass', methodName: 'exception_method'},
                segments: segments,
              }
            end

            it 'substitutes the expected value' do
              probe_manager.add_probe(probe)

              expect(component.probe_notifier_worker).to receive(:add_status) do |status|
                expect(status).to match(expected_emitting_payload)
              end
              expect(component.probe_notifier_worker).to receive(:add_snapshot) do |snapshot|
                expect(snapshot.fetch(:message)).to eq 'hello #<InstrumentationSpecTestClass::TestException>'
              end
              expect do
                InstrumentationSpecTestClass.new.exception_method
                # TODO the exception class name should be in the assertion.
              end.to raise_error(InstrumentationSpecTestClass::TestException, /Test exception/)
              component.probe_notifier_worker.flush
            end
          end
        end
      end
    end

    context 'line probe' do
      with_code_tracking

      context 'simple log probe' do
        let(:probe) do
          Datadog::DI::Probe.new(id: "1234", type: :log,
            file: 'instrumentation_integration_test_class.rb', line_no: 40,
            capture_snapshot: false,)
        end

        before do
          Object.send(:remove_const, :InstrumentationIntegrationTestClass) rescue nil
          load File.join(File.dirname(__FILE__), 'instrumentation_integration_test_class.rb')
        end

        shared_examples 'simple log probe' do
          it 'invokes probe' do
            expect(diagnostics_transport).to receive(:send_diagnostics)
            # add_snapshot expectation replaces assertion on send_input
            probe_manager.add_probe(probe)
            component.probe_notifier_worker.flush
            expect(probe_manager.installed_probes.length).to eq 1
            expect(component.probe_notifier_worker).to receive(:add_snapshot)
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
              payload.fetch(:debugger).fetch(:snapshot)
            end

            it 'does not have captures' do
              expect(diagnostics_transport).to receive(:send_diagnostics)
              # add_snapshot expectation replaces assertion on send_input
              expect(snapshot.fetch(:captures)).to eq({})
            end

            let(:stack) do
              snapshot.fetch(:stack)
            end

            let(:top_stack_frame) do
              stack.first
            end

            it 'has instrumented location as top stack frame' do
              expect(diagnostics_transport).to receive(:send_diagnostics)
              # add_snapshot expectation replaces assertion on send_input
              expect(File.basename(top_stack_frame.fetch(:fileName))).to eq 'instrumentation_integration_test_class.rb'
            end
          end
        end

        include_examples 'simple log probe'

        context 'target line is the end line of a method' do
          let(:probe) do
            Datadog::DI::Probe.new(id: "1234", type: :log,
              file: 'instrumentation_integration_test_class.rb', line_no: 42,
              capture_snapshot: false,)
          end

          include_examples 'simple log probe'
        end

        context 'target line is the end line of a block' do
          let(:probe) do
            Datadog::DI::Probe.new(id: "1234", type: :log,
              file: 'instrumentation_integration_test_class.rb', line_no: 53,
              capture_snapshot: false,)
          end

          it 'invokes probe' do
            expect(diagnostics_transport).to receive(:send_diagnostics)
            expect(input_transport).to receive(:send_input)
            probe_manager.add_probe(probe)
            component.probe_notifier_worker.flush
            expect(probe_manager.installed_probes.length).to eq 1
            expect(component.probe_notifier_worker).to receive(:add_snapshot).once.and_call_original
            expect(InstrumentationIntegrationTestClass.new.test_method_with_block).to eq([1])
            component.probe_notifier_worker.flush
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
              payload.fetch(:debugger).fetch(:snapshot)
            end

            it 'does not have captures' do
              expect(diagnostics_transport).to receive(:send_diagnostics)
              # add_snapshot expectation replaces assertion on send_input
              expect(snapshot.fetch(:captures)).to eq({})
            end

            let(:stack) do
              snapshot.fetch(:stack)
            end

            let(:top_stack_frame) do
              stack.first
            end

            it 'has instrumented location as top stack frame' do
              expect(diagnostics_transport).to receive(:send_diagnostics)
              # add_snapshot expectation replaces assertion on send_input
              expect(File.basename(top_stack_frame.fetch(:fileName))).to eq 'instrumentation_integration_test_class.rb'
            end
          end
        end

        shared_examples 'installs but does not invoke probe' do
          it 'installs but does not invoke probe' do
            expect(diagnostics_transport).to receive(:send_diagnostics)
            expect(input_transport).not_to receive(:send_input)
            probe_manager.add_probe(probe)
            component.probe_notifier_worker.flush
            expect(probe_manager.installed_probes.length).to eq 1
            expect(component.probe_notifier_worker).not_to receive(:add_snapshot)
            call_target
            component.probe_notifier_worker.flush
          end
        end

        context 'target line is else of a conditional' do
          let(:probe) do
            Datadog::DI::Probe.new(id: "1234", type: :log,
              file: 'instrumentation_integration_test_class.rb', line_no: 64,
              capture_snapshot: false,)
          end

          let(:call_target) do
            expect(InstrumentationIntegrationTestClass.new.test_method_with_conditional).to eq(1)
          end

          include_examples 'installs but does not invoke probe'
        end

        context 'target line is end of a conditional' do
          let(:probe) do
            Datadog::DI::Probe.new(id: "1234", type: :log,
              file: 'instrumentation_integration_test_class.rb', line_no: 66,
              capture_snapshot: false,)
          end

          let(:call_target) do
            expect(InstrumentationIntegrationTestClass.new.test_method_with_conditional).to eq(1)
          end

          include_examples 'installs but does not invoke probe'
        end

        context 'target line contains a comment (no executable code)' do
          let(:probe) do
            Datadog::DI::Probe.new(id: "1234", type: :log,
              file: 'instrumentation_integration_test_class.rb', line_no: 70,
              capture_snapshot: false,)
          end

          # We currently are not told that the line is not executable.
          it 'installs probe' do
            expect(probe_manager.add_probe(probe)).to be true
            expect(probe_manager.installed_probes.length).to eq 1
          end
        end

        context 'target line is in a loaded file that is not in code tracker' do
          let(:probe) do
            Datadog::DI::Probe.new(id: "1234", type: :log,
              file: 'instrumentation_integration_test_class.rb', line_no: 53,
              capture_snapshot: false,)
          end

          before do
            Object.send(:remove_const, :InstrumentationIntegrationTestClass) rescue nil
            # Files loaded via 'load' do not get added to $LOADED_FEATURES,
            # use 'require'.
            # Note that the other tests use 'load' because they want the
            # code to always be loaded.
            require_relative 'instrumentation_integration_test_class'
            expect($LOADED_FEATURES.detect do |path|
              File.basename(path) == 'instrumentation_integration_test_class.rb'
            end).to be_truthy
            component.code_tracker.clear

            # We want the probe status to be reported, therefore need to
            # disable exception propagation.
            settings.dynamic_instrumentation.internal.propagate_all_exceptions = false
          end

          it 'does not install the probe' do
            expect_lazy_log(probe_manager.logger, :debug, /File matching probe path.*was loaded and is not in code tracker registry/)
            expect do
              probe_manager.add_probe(probe)
            end.to raise_error(Datadog::DI::Error::DITargetNotInRegistry, /File matching probe path.*was loaded and is not in code tracker registry/)
            expect(probe_manager.installed_probes.length).to eq 0
          end
        end
      end

      context 'enriched probe' do
        let(:probe) do
          Datadog::DI::Probe.new(id: "1234", type: :log,
            file: 'instrumentation_integration_test_class.rb', line_no: 40,
            capture_snapshot: true,)
        end

        let(:expected_captures) do
          {lines: {40 => {
            locals: {
              a: {type: 'Integer', value: '21'},
              password: {type: 'String', notCapturedReason: 'redactedIdent'},
              redacted: {type: 'Hash', entries: [
                [{type: 'Symbol', value: 'b'}, {type: 'Integer', value: '33'}],
                [{type: 'Symbol', value: 'session'}, {type: 'String', notCapturedReason: 'redactedIdent'}],
              ]},
            },
            arguments: {
              self: {
                type: 'InstrumentationIntegrationTestClass',
                fields: {
                  "@ivar": {type: 'Integer', value: '51'},
                },
              },
            },
          }}}
        end

        before do
          Object.send(:remove_const, :InstrumentationIntegrationTestClass) rescue nil
          load File.join(File.dirname(__FILE__), 'instrumentation_integration_test_class.rb')
        end

        it 'invokes probe' do
          expect(diagnostics_transport).to receive(:send_diagnostics)
          expect(input_transport).to receive(:send_input)
          probe_manager.add_probe(probe)
          expect(component.probe_notifier_worker).to receive(:add_snapshot).once.and_call_original
          expect(InstrumentationIntegrationTestClass.new.test_method).to eq(42)
          component.probe_notifier_worker.flush
        end

        shared_examples 'assembles expected notification payload' do
          it 'assembles expected notification payload' do
            expect(diagnostics_transport).to receive(:send_diagnostics)
            # add_snapshot expectation replaces assertion on send_input
            probe_manager.add_probe(probe)
            payload = nil
            expect(component.probe_notifier_worker).to receive(:add_snapshot) do |payload_|
              payload = payload_
            end
            expect(InstrumentationIntegrationTestClass.new.public_send(test_method_name)).to eq(42)
            component.probe_notifier_worker.flush

            expect(payload).to be_a(Hash)
            captures = payload.fetch(:debugger).fetch(:snapshot).fetch(:captures)
            expect(captures).to eq(expected_captures)
          end
        end

        let(:test_method_name) { :test_method }

        include_examples 'assembles expected notification payload'

        context 'when there are instance variables but no local variables' do
          let(:probe) do
            Datadog::DI::Probe.new(id: "1234", type: :log,
              file: 'instrumentation_integration_test_class.rb', line_no: 27,
              capture_snapshot: true,)
          end

          let(:expected_captures) do
            {lines: {27 => {
              # Reports instance variables but no locals
              locals: {},
              arguments: {
                self: {
                  type: 'InstrumentationIntegrationTestClass',
                  fields: {
                    "@ivar": {type: 'Integer', value: '51'},
                  },
                },
              },
            }}}
          end

          let(:test_method_name) { :method_with_no_locals }

          include_examples 'assembles expected notification payload'
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
            expect(diagnostics_transport).to receive(:send_diagnostics)
            expect(input_transport).to receive(:send_input)

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
              expect(diagnostics_transport).to receive(:send_diagnostics)
              expect(input_transport).to receive(:send_input)

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
                file: 'instrumentation_integration_test_class_4.rb', line_no: 20,)
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
            file: 'instrumentation_integration_test_class.rb', line_no: 40,
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
