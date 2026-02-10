require 'spec_helper'
require 'datadog/di/spec_helper'

class EverythingFromRemoteConfigSpecTestClass
  def target_method
    42
  end
end

RSpec.describe 'DI integration from remote config' do
  di_test
  skip_unless_integration_testing_enabled

  let(:remote) { Datadog::DI::Remote }
  let(:path) { 'datadog/2/LIVE_DEBUGGING/logProbe_uuid/hash' }

  before(:all) do
    # if code tracking is active, it invokes methods on mock objects
    # used in these tests.
    Datadog::DI.deactivate_tracking!
  end

  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

  let(:logger) { instance_double(Logger) }

  let(:repository) { Datadog::Core::Remote::Configuration::Repository.new }

  let(:transaction) do
    DIHelpers::TestRemoteConfigGenerator.new(probe_configs).insert_transaction(repository)
  end

  let(:probe_configs) do
    {'datadog/2/LIVE_DEBUGGING/foo/bar' => probe_spec}
  end

  let(:receiver) { remote.receivers(telemetry)[0] }

  let(:component) do
    # TODO should this use Component.new? We have to manually pass in
    # the code tracker in that case.
    Datadog::DI::Component.build(settings, agent_settings, logger).tap do |component|
      if component.nil?
        raise "Component failed to create - unsuitable environment? Check log entries"
      end
    end
  end

  let(:propagate_all_exceptions) { true }

  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |settings|
      settings.remote.enabled = true
      settings.dynamic_instrumentation.enabled = true
      settings.dynamic_instrumentation.internal.development = true
      settings.dynamic_instrumentation.internal.propagate_all_exceptions = propagate_all_exceptions
    end
  end

  let(:serializer) do
    component.serializer
  end

  let(:instrumenter) do
    component.instrumenter
  end

  let(:probe_manager) do
    component.probe_manager
  end

  after do
    component.shutdown!
  end

  let(:agent_settings) do
    instance_double_agent_settings_with_stubs
  end

  let(:stringified_probe_spec) do
    JSON.parse(probe_spec.to_json)
  end

  before do
    expect(Datadog::DI).to receive(:component).at_least(:once).and_return(component)
  end

  let(:mock_response) do
    instance_double(Datadog::Core::Transport::HTTP::Response).tap do |response|
      expect(response).to receive(:ok?).at_least(:once).and_return(true)
    end
  end

  let(:expected_received_payload) do
    {
      path: '/debugger/v1/diagnostics',
      ddsource: 'dd_debugger',
      debugger: {
        diagnostics: {
          parentId: nil,
          probeId: '11',
          probeVersion: 0,
          runtimeId: be_valid_uuid,
          status: 'RECEIVED',
        },
      },
      message: 'Probe 11 has been received correctly',
      service: 'rspec',
      timestamp: Integer,
    }
  end

  let(:expected_installed_payload) do
    {
      path: '/debugger/v1/diagnostics',
      ddsource: 'dd_debugger',
      debugger: {
        diagnostics: {
          parentId: nil,
          probeId: '11',
          probeVersion: 0,
          runtimeId: be_valid_uuid,
          status: 'INSTALLED',
        },
      },
      message: 'Probe 11 has been instrumented correctly',
      service: 'rspec',
      timestamp: Integer,
    }
  end

  let(:expected_emitting_payload) do
    {
      path: '/debugger/v1/diagnostics',
      ddsource: 'dd_debugger',
      debugger: {
        diagnostics: {
          parentId: nil,
          probeId: '11',
          probeVersion: 0,
          runtimeId: be_valid_uuid,
          status: 'EMITTING',
        },
      },
      message: 'Probe 11 is emitting',
      service: 'rspec',
      timestamp: Integer,
    }
  end

  let(:expected_errored_payload) do
    {
      path: '/debugger/v1/diagnostics',
      ddsource: 'dd_debugger',
      debugger: {
        diagnostics: {
          parentId: nil,
          probeId: '11',
          probeVersion: 0,
          runtimeId: be_valid_uuid,
          status: 'ERROR',
        },
      },
      message: /Instrumentation for probe 11 failed: File matching probe path \(instrumentation_integration_test_class.rb\) was loaded and is not in code tracker registry:/,
      service: 'rspec',
      timestamp: Integer,
    }
  end

  let(:expected_snapshot_payload) do
    {
      path: '/debugger/v1/input',
      # We do not have active span/trace in the test.
      "dd.span_id": nil,
      "dd.trace_id": nil,
      debugger: {
        type: 'snapshot',
        snapshot: {
          captures: {},
          evaluationErrors: [],
          id: be_valid_uuid,
          language: 'ruby',
          probe: {
            id: '11',
            location: {
              method: 'target_method',
              type: 'EverythingFromRemoteConfigSpecTestClass',
            },
            version: 0,
          },
          stack: Array,
          timestamp: Integer,
        },
      },
      ddsource: 'dd_debugger',
      duration: Integer,
      host: nil,
      logger: {
        method: 'target_method',
        name: nil,
        thread_id: nil,
        thread_name: 'Thread.main',
        version: 2,
      },
      message: nil,
      service: 'rspec',
      timestamp: Integer,
    }
  end

  let(:payloads) { [] }

  let(:diagnostics_transport) do
    double(Datadog::DI::Transport::Diagnostics::Transport)
  end

  let(:input_transport) do
    double(Datadog::DI::Transport::Input::Transport)
  end

  def do_rc(expect_add_probe: true, expect_hook: :hook_method)
    if expect_add_probe
      expect(probe_manager).to receive(:add_probe).and_call_original
    else
      # If we do not make it past probe addition, there will not be hooking
      expect_hook = false
    end

    if expect_hook
      expect(instrumenter).to receive(expect_hook).and_call_original
    end

    expect(Datadog::DI::Transport::HTTP).to receive(:diagnostics).and_return(diagnostics_transport)
    allow(Datadog::DI::Transport::HTTP).to receive(:input).and_return(input_transport)
    expect(diagnostics_transport).to receive(:send_diagnostics).at_least(:once) do |notify_payload|
      expect(notify_payload).to be_a(Array)
      notify_payload.each do |payload|
        payloads << payload.merge(path: '/debugger/v1/diagnostics')
      end
    end
    allow(input_transport).to receive(:send_input) do |notify_payload|
      expect(notify_payload).to be_a(Array)
      notify_payload.each do |payload|
        # Quick hack to deep stringify keys
        payload = JSON.parse(payload.to_json)
        payloads << payload.merge(path: '/debugger/v1/input')
      end
    end

    receiver.call(repository, transaction)

    component.probe_notifier_worker.flush
  end

  context 'method probe received not matching a loaded class' do
    let(:probe_spec) do
      {id: '11', name: 'bar', type: 'LOG_PROBE', where: {typeName: 'Foo', methodName: 'bar'}}
    end

    it 'adds a probe to pending list' do
      expect_lazy_log(logger, :debug, /received log probe at .+ via RC/)

      do_rc

      expect(payloads).to be_a(Array)
      expect(payloads.length).to eq 1

      received_payload = payloads.first
      expect(order_hash_keys(received_payload)).to match(order_hash_keys(expected_received_payload))

      expect(probe_manager.pending_probes.length).to eq 1
    end
  end

  def assert_received_and_installed
    expect(payloads).to be_a(Array)
    expect(payloads.length).to eq 2

    received_payload = payloads.shift
    expect(received_payload).to match(expected_received_payload)

    installed_payload = payloads.shift
    expect(installed_payload).to match(expected_installed_payload)
  end

  def assert_received_and_errored
    expect(payloads).to be_a(Array)
    expect(payloads.length).to eq 2

    received_payload = payloads.shift
    expect(received_payload).to match(expected_received_payload)

    installed_payload = payloads.shift
    expect(installed_payload).to match(expected_errored_payload)
  end

  context 'method probe received matching a loaded class' do
    let(:probe_spec) do
      {id: '11', name: 'bar', type: 'LOG_PROBE', where: {typeName: 'EverythingFromRemoteConfigSpecTestClass', methodName: 'target_method'}}
    end

    it 'instruments code and adds probe to installed list' do
      expect_lazy_log(logger, :debug, /received log probe at .+ via RC/)

      do_rc
      assert_received_and_installed

      expect(probe_manager.installed_probes.length).to eq 1
    end

    context 'and target method is invoked' do
      it 'notifies about execution' do
        expect_lazy_log(logger, :debug, /received log probe at .+ via RC/)

        do_rc
        assert_received_and_installed

        expect(probe_manager.installed_probes.length).to eq 1

        # Payloads array should have been cleared out in do_rc
        expect(payloads.length).to eq 0

        # invocation

        EverythingFromRemoteConfigSpecTestClass.new.target_method

        component.probe_notifier_worker.flush

        # assertions

        expect(payloads.length).to eq 2

        emitting_payload = payloads.shift
        expect(emitting_payload).to match(expected_emitting_payload)

        snapshot_payload = payloads.shift
        expect(order_hash_keys(snapshot_payload)).to match(deep_stringify_keys(order_hash_keys(expected_snapshot_payload)))
      end
    end

    context 'unknown type probe followed by method probe' do
      # If exceptions are propagated, remote config processing will stop
      # at the first, failing, probe specification.
      let(:propagate_all_exceptions) { false }

      let(:unknown_probe_spec) do
        {id: '12', name: 'foo', type: 'UNKNOWN_PROBE'}
      end

      let(:probe_configs) do
        {'datadog/2/LIVE_DEBUGGING/foo1/bar1' => unknown_probe_spec,
         'datadog/2/LIVE_DEBUGGING/foo2/bar2' => probe_spec}
      end

      it 'installs the second, known, probe' do
        expect_lazy_log(logger, :debug, /Unrecognized probe type:/)
        expect_lazy_log(logger, :debug, /received log probe at .+ via RC/)

        do_rc

        expect(payloads.length).to be 3
        payload = payloads.shift
        expect(payload).to be_a(Hash)
        expect(payload[:message]).to match(
          /Instrumentation for probe .* failed: Unrecognized probe type: UNKNOWN_PROBE/,
        )

        assert_received_and_installed

        expect(probe_manager.installed_probes.length).to eq 1
      end
    end

    context 'invalid expression language expression' do
      let(:probe_spec) do
        {
          id: '11', name: 'bar', type: 'LOG_PROBE',
          where: {
            typeName: 'EverythingFromRemoteConfigSpecTestClass', methodName: 'target_method',
          },
          when: {json: {foo: 'bar'}, dsl: '(expression)'},
        }
      end

      let(:propagate_all_exceptions) { false }

      it 'catches the exception and reports probe status error' do
        expect_lazy_log(logger, :debug, /di: unhandled exception handling a probe in DI remote receiver: Datadog::DI::Error::InvalidExpression: Unknown operation: foo/)

        do_rc(expect_add_probe: false)
        expect(probe_manager.installed_probes.length).to eq 0

        payload = payloads.first
        expect(payload).to be_a(Hash)
        expect(payload).to match(
          ddsource: 'dd_debugger',
          debugger: {
            diagnostics: {
              parentId: nil,
              probeId: '11',
              probeVersion: 0,
              runtimeId: String,
              status: 'ERROR',
            },
          },
          path: '/debugger/v1/diagnostics',
          service: 'rspec',
          timestamp: Integer,
          message: String,
        )
        expect(payload[:message]).to match(
          /Instrumentation for probe .* failed: Unknown operation: foo/,
        )
      end
    end

    context 'when there is a message template' do
      let(:probe_spec) do
        {
          id: '11', name: 'bar', type: 'LOG_PROBE',
          where: {
            typeName: 'EverythingFromRemoteConfigSpecTestClass', methodName: 'target_method',
          },
          segments: [
            # String segment
            {str: 'hello '},
            # Expression segment - valid at runtime
            {json: {eq: [{ref: '@ivar'}, 51]}, dsl: '(good expression)'},
            # Another expression which fails evaluation at runtime
            {json: {filter: [{ref: '@ivar'}, 'x']}, dsl: '(failing expression)'},
          ],
        }
      end

      let(:expected_snapshot_payload) do
        {
          path: '/debugger/v1/input',
          # We do not have active span/trace in the test.
          "dd.span_id": nil,
          "dd.trace_id": nil,
          debugger: {
            type: 'snapshot',
            snapshot: {
              captures: {},
              evaluationErrors: [
                {'expr' => '(failing expression)', 'message' => 'Datadog::DI::Error::ExpressionEvaluationError: Bad collection type for filter: NilClass'},
              ],
              id: be_valid_uuid,
              language: 'ruby',
              probe: {
                id: '11',
                location: {
                  method: 'target_method',
                  type: 'EverythingFromRemoteConfigSpecTestClass',
                },
                version: 0,
              },
              stack: Array,
              timestamp: Integer,
            },
          },
          ddsource: 'dd_debugger',
          duration: Integer,
          host: nil,
          logger: {
            method: 'target_method',
            name: nil,
            thread_id: nil,
            thread_name: 'Thread.main',
            version: 2,
          },
          # false is the result of first expression evaluation
          # second expression fails evaluation
          message: 'hello false[evaluation error]',
          service: 'rspec',
          timestamp: Integer,
        }
      end

      it 'evaluates expressions and reports errors' do
        expect_lazy_log(logger, :debug, /di: received log probe/)

        do_rc
        assert_received_and_installed

        # invocation

        expect(EverythingFromRemoteConfigSpecTestClass.new.target_method).to eq 42

        component.probe_notifier_worker.flush

        # assertions

        expect(payloads.length).to eq 2

        emitting_payload = payloads.shift
        expect(emitting_payload).to match(expected_emitting_payload)

        snapshot_payload = payloads.shift
        expect(order_hash_keys(snapshot_payload)).to match(deep_stringify_keys(order_hash_keys(expected_snapshot_payload)))
      end
    end
  end

  context 'line probe' do
    with_code_tracking

    shared_context 'targeting integration test class via load' do
      before do
        begin
          Object.send(:remove_const, :InstrumentationIntegrationTestClass)
        rescue
          nil
        end
        load File.join(File.dirname(__FILE__), 'instrumentation_integration_test_class.rb')

        # We want the probe status to be reported, therefore need to
        # disable exception propagation.
        settings.dynamic_instrumentation.internal.propagate_all_exceptions = false
      end
    end

    shared_context 'targeting integration test class via require' do
      before do
        begin
          Object.send(:remove_const, :InstrumentationIntegrationTestClass)
        rescue
          nil
        end
        # Files loaded via 'load' do not get added to $LOADED_FEATURES,
        # use 'require'.
        # Note that the other tests use 'load' because they want the
        # code to always be loaded.
        require_relative 'instrumentation_integration_test_class'
        expect($LOADED_FEATURES.detect do |path|
          File.basename(path) == 'instrumentation_integration_test_class.rb'
        end).to be_truthy

        # We want the probe status to be reported, therefore need to
        # disable exception propagation.
        settings.dynamic_instrumentation.internal.propagate_all_exceptions = false
      end
    end

    context 'line probe with path containing extra prefix directories' do
      let(:probe_spec) do
        {id: '11', name: 'bar', type: 'LOG_PROBE', where: {
          sourceFile: 'junk/prefix/instrumentation_integration_test_class.rb', lines: [42]
        }}
      end

      include_context 'targeting integration test class via load'

      it 'instruments code and adds probe to installed list' do
        expect_lazy_log(logger, :debug, /received log probe at .+ via RC/)

        do_rc(expect_hook: :hook_line)
        assert_received_and_installed

        expect(probe_manager.installed_probes.length).to eq 1
      end
    end

    context 'line probe received targeting loaded code not in code tracker' do
      let(:probe_spec) do
        {id: '11', name: 'bar', type: 'LOG_PROBE', where: {
          sourceFile: 'instrumentation_integration_test_class.rb', lines: [42]
        }}
      end

      include_context 'targeting integration test class via require'

      before do
        component.code_tracker.clear
      end

      it 'marks RC payload as errored' do
        expect_lazy_log_many(logger, :debug,
          /received log probe at .+ via RC/,
          /error processing probe configuration:.*File matching probe path.*was loaded and is not in code tracker registry/,)

        do_rc(expect_hook: false)
        assert_received_and_errored

        expect(probe_manager.installed_probes.length).to eq 0
      end
    end

    context 'when condition evaluation fails at runtime' do
      with_code_tracking

      let(:propagate_all_exceptions) { true }

      let(:probe_spec) do
        {
          id: '11', name: 'bar', type: 'LOG_PROBE',
          where: {
            sourceFile: 'instrumentation_integration_test_class.rb', lines: [42],
          },
          when: {json: {'contains' => [{'ref' => 'bar'}, 'baz']}, dsl: '(expression)'},
        }
      end

      before do
        load File.join(File.dirname(__FILE__), 'instrumentation_integration_test_class.rb')
      end

      let(:evaluation_error_message) do
        'Datadog::DI::Error::ExpressionEvaluationError: Invalid arguments for contains: , baz'
      end

      let(:expected_snapshot_payload) do
        {
          path: '/debugger/v1/input',
          # We do not have active span/trace in the test.
          "dd.span_id": nil,
          "dd.trace_id": nil,
          debugger: {
            type: 'snapshot',
            snapshot: {
              captures: {},
              evaluationErrors: [
                {'expr' => '(expression)', 'message' => evaluation_error_message},
              ],
              id: be_valid_uuid,
              language: 'ruby',
              probe: {
                id: '11',
                location: {
                  file: String,
                  lines: [String],
                },
                version: 0,
              },
              stack: Array,
              timestamp: Integer,
            },
          },
          ddsource: 'dd_debugger',
          duration: Integer,
          host: nil,
          logger: {
            method: nil,
            name: 'instrumentation_integration_test_class.rb',
            thread_id: nil,
            thread_name: 'Thread.main',
            version: 2,
          },
          # No message since we stopped execution at condition evaluation.
          message: nil,
          service: 'rspec',
          timestamp: Integer,
        }
      end

      it 'executes target code still and notifies about failed condition evaluation' do
        expect_lazy_log(logger, :debug, /received log probe at .+ via RC/)
        do_rc(expect_hook: :hook_line)
        assert_received_and_installed

        expect(probe_manager.installed_probes.length).to eq 1
        probe = probe_manager.installed_probes.values.first
        expect(probe.condition).to be_a(Datadog::DI::EL::Expression)

        rv = InstrumentationIntegrationTestClass.new.test_method
        expect(rv).to eq 42

        component.probe_notifier_worker.flush

        # assertions

        expect(payloads.length).to eq 1

        # No emitting payload because the probe hasn't emitted anything yet.
        #emitting_payload = payloads.shift
        #expect(emitting_payload).to match(expected_emitting_payload)

        snapshot_payload = payloads.shift
        expect(order_hash_keys(snapshot_payload)).to match(deep_stringify_keys(order_hash_keys(expected_snapshot_payload)))
      end

      context 'when second invocation successfully evaluates condition' do
        let(:probe_spec) do
          {
            id: '11', name: 'bar', type: 'LOG_PROBE',
            where: {
              sourceFile: 'instrumentation_integration_test_class.rb', lines: [67],
            },
            when: {json: {'contains' => [{'ref' => 'param'}, 'baz']}, dsl: '(expression)'},
          }
        end

        let(:evaluation_error_message) do
          'Datadog::DI::Error::ExpressionEvaluationError: Invalid arguments for contains: false, baz'
        end

        let(:expected_captures) { {} }

        let(:expected_second_snapshot_payload) do
          {
            path: '/debugger/v1/input',
            # We do not have active span/trace in the test.
            "dd.span_id": nil,
            "dd.trace_id": nil,
            debugger: {
              type: 'snapshot',
              snapshot: {
                captures: expected_captures,
                evaluationErrors: [],
                id: be_valid_uuid,
                language: 'ruby',
                probe: {
                  id: '11',
                  location: {
                    file: File.join(File.dirname(__FILE__), 'instrumentation_integration_test_class.rb'),
                    lines: ['67'],
                  },
                  version: 0,
                },
                stack: Array,
                timestamp: Integer,
              },
            },
            ddsource: 'dd_debugger',
            duration: Integer,
            host: nil,
            logger: {
              method: nil,
              name: 'instrumentation_integration_test_class.rb',
              thread_id: nil,
              thread_name: 'Thread.main',
              version: 2,
            },
            message: nil,
            service: 'rspec',
            timestamp: Integer,
          }
        end

        it 'notifies emitting on second invocation' do
          expect_lazy_log(logger, :debug, /received log probe at .+ via RC/)
          do_rc(expect_hook: :hook_line)
          assert_received_and_installed

          expect(probe_manager.installed_probes.length).to eq 1
          probe = probe_manager.installed_probes.values.first
          expect(probe.condition).to be_a(Datadog::DI::EL::Expression)

          rv = InstrumentationIntegrationTestClass.new.test_method_with_conditional
          expect(rv).to eq 1

          component.probe_notifier_worker.flush

          # assertions

          expect(payloads.length).to eq 1

          # No emitting payload because the probe hasn't emitted anything yet.
          #emitting_payload = payloads.shift
          #expect(emitting_payload).to match(expected_emitting_payload)

          snapshot_payload = payloads.shift
          expect(order_hash_keys(snapshot_payload)).to match(deep_stringify_keys(order_hash_keys(expected_snapshot_payload)))

          # Second call with a different type of value passed in as parameter.
          # Condition evaluation does not raise an exception but
          # the condition is not met.
          rv = InstrumentationIntegrationTestClass.new.test_method_with_conditional('hello foo')
          expect(rv).to eq 2

          component.probe_notifier_worker.flush

          # assertions

          # No new payloads since condition wasn't met and probe
          # was not executed.
          expect(payloads.length).to eq 0

          # Condition is met for this invocation.
          rv = InstrumentationIntegrationTestClass.new.test_method_with_conditional('hello baz')
          expect(rv).to eq 2

          component.probe_notifier_worker.flush

          # assertions

          expect(payloads.length).to eq 2

          emitting_payload = payloads.shift
          expect(emitting_payload).to match(expected_emitting_payload)

          snapshot_payload = payloads.shift
          expect(order_hash_keys(snapshot_payload)).to match(deep_stringify_keys(order_hash_keys(expected_second_snapshot_payload)))
        end

        context 'when code is invoked several times' do
          let(:probe_spec) do
            {
              id: '11', name: 'bar', type: 'LOG_PROBE',
              where: {
                sourceFile: 'instrumentation_integration_test_class.rb', lines: [67],
              },
              when: {json: {'contains' => [{'ref' => 'param'}, 'baz']}, dsl: '(expression)'},
              # Enable snapshot capture to get the lower rate limit (1/second)
              captureSnapshot: true,
            }
          end

          let(:expected_captures) { Hash }

          it 'respects rate limits' do
            expect_lazy_log(logger, :debug, /received log probe at .+ via RC/)
            do_rc(expect_hook: :hook_line)
            assert_received_and_installed

            expect(probe_manager.installed_probes.length).to eq 1
            probe = probe_manager.installed_probes.values.first
            expect(probe.condition).to be_a(Datadog::DI::EL::Expression)

            rv = InstrumentationIntegrationTestClass.new.test_method_with_conditional
            expect(rv).to eq 1

            component.probe_notifier_worker.flush

            # assertions

            expect(payloads.length).to eq 1

            # No emitting payload because the probe hasn't emitted anything yet.
            #emitting_payload = payloads.shift
            #expect(emitting_payload).to match(expected_emitting_payload)

            snapshot_payload = payloads.shift
            expect(order_hash_keys(snapshot_payload)).to match(deep_stringify_keys(order_hash_keys(expected_snapshot_payload)))

            # Identical call - will not cause anything to be emitted
            # due to rate limit on evaluation error reporting.

            rv = InstrumentationIntegrationTestClass.new.test_method_with_conditional
            expect(rv).to eq 1

            component.probe_notifier_worker.flush

            expect(payloads.length).to eq 0

            # Condition is met for this invocation.
            rv = InstrumentationIntegrationTestClass.new.test_method_with_conditional('hello baz')
            expect(rv).to eq 2

            component.probe_notifier_worker.flush

            # assertions

            expect(payloads.length).to eq 2

            emitting_payload = payloads.shift
            expect(emitting_payload).to match(expected_emitting_payload)

            snapshot_payload = payloads.shift
            expect(order_hash_keys(snapshot_payload)).to match(deep_stringify_keys(order_hash_keys(expected_second_snapshot_payload)))

            # Call again - no payloads emitted because of rate limit.
            rv = InstrumentationIntegrationTestClass.new.test_method_with_conditional('hello baz')
            expect(rv).to eq 2

            component.probe_notifier_worker.flush

            # assertions

            expect(payloads.length).to eq 0
          end
        end
      end
    end
  end
end
