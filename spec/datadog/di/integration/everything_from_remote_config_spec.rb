require 'spec_helper'
require 'datadog/di/spec_helper'

class EverythingFromRemoteConfigSpecTestClass
  def target_method
    42
  end
end

LOWERCASE_UUID_REGEXP = /\A[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}\z/

RSpec.describe 'DI integration from remote config' do
  di_test

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
    repository.transaction do |_repository, transaction|
      probe_configs.each do |key, value|
        value_json = value.to_json

        target = Datadog::Core::Remote::Configuration::Target.parse(
          {
            'custom' => {
              'v' => 1,
            },
            'hashes' => {'sha256' => Digest::SHA256.hexdigest(value_json.to_json)},
            'length' => value_json.length
          }
        )

        content = Datadog::Core::Remote::Configuration::Content.parse(
          {
            path: key,
            content: StringIO.new(value_json),
          }
        )

        transaction.insert(content.path, target, content)
      end
    end
  end

  let(:probe_configs) do
    {'datadog/2/LIVE_DEBUGGING/foo/bar' => probe_spec}
  end

  let(:receiver) { remote.receivers(telemetry)[0] }

  let(:component) do
    Datadog::DI::Component.build!(settings, agent_settings, logger)
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
    instance_double_agent_settings.tap do |agent_settings|
      allow(agent_settings).to receive(:hostname)
      allow(agent_settings).to receive(:port)
      allow(agent_settings).to receive(:timeout_seconds).and_return(1)
      allow(agent_settings).to receive(:ssl)
    end
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
          runtimeId: LOWERCASE_UUID_REGEXP,
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
          runtimeId: LOWERCASE_UUID_REGEXP,
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
          runtimeId: LOWERCASE_UUID_REGEXP,
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
          runtimeId: LOWERCASE_UUID_REGEXP,
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
      "debugger.snapshot": {
        captures: nil,
        evaluationErrors: [],
        id: LOWERCASE_UUID_REGEXP,
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

  def do_rc(expect_hook: :hook_method)
    expect(probe_manager).to receive(:add_probe).and_call_original
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
        assert_received_and_installed

        expect(probe_manager.installed_probes.length).to eq 1
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
          sourceFile: 'junk/prefix/instrumentation_integration_test_class.rb', lines: [22]
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
          sourceFile: 'instrumentation_integration_test_class.rb', lines: [22]
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
  end
end
