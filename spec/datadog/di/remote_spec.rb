require "datadog/di/spec_helper"
require 'datadog/di'
require 'spec_helper'
require 'logger'

RSpec.describe Datadog::DI::Remote do
  di_test

  let(:remote) { described_class }
  let(:path) { 'datadog/2/LIVE_DEBUGGING/logProbe_uuid/hash' }

  before(:all) do
    # if code tracking is active, it invokes methods on mock objects
    # used in these tests.
    Datadog::DI.deactivate_tracking!
  end

  it 'declares the LIVE_DEBUGGING product' do
    expect(remote.products).to contain_exactly('LIVE_DEBUGGING')
  end

  it 'declares no capabilities' do
    # DI enablement capability (bit 38) is declared by Tracing::Remote,
    # not DI::Remote, because it's an APM_TRACING capability.
    expect(remote.capabilities).to eq []
  end

  it 'declares matches that match APM_TRACING' do
    telemetry = instance_double(Datadog::Core::Telemetry::Component)

    expect(remote.receivers(telemetry)).to all(
      match(
        lambda do |receiver|
          receiver.match? Datadog::Core::Remote::Configuration::Path.parse(path)
        end
      )
    )
  end

  describe '.handle_rc_enablement' do
    # Verifies the RC-driven enable/disable path invoked from
    # Datadog::Tracing::Remote when `dynamic_instrumentation_enabled`
    # arrives in an APM_TRACING payload. This is the entire entry
    # point for the implicit-enablement feature.

    let(:component) { instance_double(Datadog::DI::Component) }
    let(:components) { instance_double(Datadog::Core::Configuration::Components, dynamic_instrumentation: component) }

    before do
      allow(Datadog).to receive(:send).with(:components).and_return(components)
    end

    context 'when enabled: true and component is not explicitly disabled' do
      before do
        allow(described_class).to receive(:explicitly_disabled?).and_return(false)
      end

      it 'activates tracking and starts the component' do
        expect(Datadog::DI).to receive(:activate_tracking)
        expect(component).to receive(:start!)
        described_class.handle_rc_enablement(true)
      end
    end

    context 'when enabled: true and component is explicitly disabled (env var false)' do
      before do
        allow(described_class).to receive(:explicitly_disabled?).and_return(true)
      end

      it 'does not start the component (env var takes precedence) and warns' do
        expect(Datadog::DI).not_to receive(:activate_tracking)
        expect(component).not_to receive(:start!)
        expect(Datadog.logger).to receive(:warn).with(
          a_string_matching(/ignoring implicit enablement signal.*DD_DYNAMIC_INSTRUMENTATION_ENABLED.*explicitly set to false/)
        )
        described_class.handle_rc_enablement(true)
      end
    end

    context 'when enabled: false' do
      it 'stops the component (idempotent — also stops if not started)' do
        expect(component).to receive(:stop!)
        described_class.handle_rc_enablement(false)
      end
    end

    context 'when component is nil (DI not built)' do
      let(:components) { instance_double(Datadog::Core::Configuration::Components, dynamic_instrumentation: nil) }

      context 'on enable=true' do
        # The component is nil because Component.build returned nil at startup.
        # The customer who clicked "create probe" in the UI deserves the same
        # visibility a customer who set DD_DYNAMIC_INSTRUMENTATION_ENABLED
        # would have gotten at boot.
        it 'does not activate tracking and warns naming the unsupported reason' do
          allow(Datadog::DI).to receive(:unsupported_reason).and_return("MRI is required, but running on jruby")
          expect(Datadog::DI).not_to receive(:activate_tracking)
          expect(Datadog.logger).to receive(:warn).with(
            a_string_matching(/cannot enable dynamic instrumentation via remote configuration.*MRI is required.*jruby/)
          )
          described_class.handle_rc_enablement(true)
        end

        it 'falls back to a generic message when no reason is available' do
          allow(Datadog::DI).to receive(:unsupported_reason).and_return(nil)
          expect(Datadog.logger).to receive(:warn).with(
            a_string_matching(/cannot enable dynamic instrumentation via remote configuration.*was not initialized at startup/)
          )
          described_class.handle_rc_enablement(true)
        end
      end

      context 'on enable=false' do
        it 'is a silent no-op' do
          # RC asking to disable something we don't have is fine — no warn needed.
          expect(Datadog.logger).not_to receive(:warn)
          expect { described_class.handle_rc_enablement(false) }.not_to raise_error
        end
      end
    end

    context 'when an exception is raised inside the body' do
      let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
      let(:components) do
        instance_double(
          Datadog::Core::Configuration::Components,
          dynamic_instrumentation: component,
          telemetry: telemetry,
        )
      end

      before do
        allow(described_class).to receive(:explicitly_disabled?).and_return(false)
        allow(Datadog::DI).to receive(:activate_tracking)
        allow(component).to receive(:start!).and_raise(RuntimeError, 'boom')
      end

      it 'logs at debug and reports to telemetry, does not raise' do
        expect(Datadog.logger).to receive(:debug) do |&block|
          expect(block.call).to match(/error handling implicit enablement.*RuntimeError.*boom/)
        end
        expect(telemetry).to receive(:report).with(an_instance_of(RuntimeError), description: /implicit enablement/)
        expect { described_class.handle_rc_enablement(true) }.not_to raise_error
      end
    end
  end

  describe '.handle_rc_enablement settings invariant (test 23)' do
    # Guards the "RC only enables/disables" decision in design/architecture.md.
    # RC must never mutate settings under settings.dynamic_instrumentation —
    # those are injected at component build time and remain authoritative
    # through start!/stop!. If a future change accidentally routes a settings
    # update through this path, this snapshot diff catches it.

    let(:component) { instance_double(Datadog::DI::Component, start!: nil, stop!: nil) }
    let(:components) { instance_double(Datadog::Core::Configuration::Components, dynamic_instrumentation: component) }
    let(:settings) do
      Datadog::Core::Configuration::Settings.new.tap do |s|
        # Touch DI settings so the option hash is fully materialized and the
        # snapshot covers every defined option.
        s.dynamic_instrumentation.enabled
        s.dynamic_instrumentation.redacted_identifiers
        s.dynamic_instrumentation.max_capture_depth
      end
    end

    before do
      allow(Datadog).to receive(:send).and_call_original
      allow(Datadog).to receive(:send).with(:components).and_return(components)
      allow(Datadog).to receive(:configuration).and_return(settings)
      allow(described_class).to receive(:explicitly_disabled?).and_return(false)
      allow(Datadog::DI).to receive(:activate_tracking)
    end

    def options_snapshot(di_settings)
      di_settings.options.transform_values do |opt|
        # Capture the current value AND the precedence so a change in either
        # would be detected. Some options have nested settings hashes, so we
        # also walk those.
        [opt.get, opt.send(:precedence_set)]
      end
    end

    it 'leaves dynamic_instrumentation settings unchanged after enable=true' do
      before_snap = options_snapshot(settings.dynamic_instrumentation)
      described_class.handle_rc_enablement(true)
      after_snap = options_snapshot(settings.dynamic_instrumentation)
      expect(after_snap).to eq before_snap
    end

    it 'leaves dynamic_instrumentation settings unchanged after enable=false' do
      before_snap = options_snapshot(settings.dynamic_instrumentation)
      described_class.handle_rc_enablement(false)
      after_snap = options_snapshot(settings.dynamic_instrumentation)
      expect(after_snap).to eq before_snap
    end
  end

  describe '.explicitly_disabled?' do
    # The precedence rule between env var and RC: env var
    # `DD_DYNAMIC_INSTRUMENTATION_ENABLED=false` blocks RC enablement.
    # An unset env var (default_precedence?) does not.

    let(:settings) { Datadog::Core::Configuration::Settings.new }
    let(:di_settings) { settings.dynamic_instrumentation }

    before do
      allow(Datadog).to receive(:configuration).and_return(settings)
    end

    context 'when called before any code has touched dynamic_instrumentation.enabled' do
      # The option hash is lazy-initialized; reading
      # options[:enabled].default_precedence? without first touching the
      # getter would NoMethodError on nil. using_default? materializes the
      # option as needed.
      it 'returns false without raising' do
        expect { described_class.explicitly_disabled? }.not_to raise_error
        expect(described_class.explicitly_disabled?).to be false
      end
    end

    context 'when the env var is unset (default precedence) and enabled remains default false' do
      before do
        di_settings.enabled
      end

      it 'returns false (RC may enable)' do
        expect(described_class.explicitly_disabled?).to be false
      end
    end

    context 'when the env var is explicitly set to false by the customer' do
      before do
        di_settings.enabled = false
      end

      it 'returns true (RC enablement is blocked)' do
        expect(described_class.explicitly_disabled?).to be true
      end
    end

    context 'when the env var is explicitly set to true' do
      before do
        di_settings.enabled = true
      end

      it 'returns false (explicitly enabled — RC may also try to enable)' do
        expect(described_class.explicitly_disabled?).to be false
      end
    end
  end

  describe '.receivers' do
    let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

    it 'returns receivers' do
      receivers = described_class.receivers(telemetry)
      expect(receivers.size).to eq(1)
      expect(receivers.first).to be_a(Datadog::Core::Remote::Dispatcher::Receiver)
    end

    describe 'receiver logic' do
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
                content: value_json,
              }
            )

            transaction.insert(content.path, target, content)
          end
        end
      end

      let(:probe_configs) do
        {'datadog/2/LIVE_DEBUGGING/foo/bar' => probe_spec}
      end

      let(:receiver) { described_class.receivers(telemetry)[0] }

      let(:probe_notifier_worker) do
        instance_double(Datadog::DI::ProbeNotifierWorker)
      end

      let(:component) do
        instance_double(Datadog::DI::Component).tap do |component|
          expect(component).to receive(:probe_manager).and_return(probe_manager)
          allow(component).to receive(:settings).and_return(settings)
          allow(component).to receive(:started?).and_return(true)
        end
      end

      mock_settings_for_di do |settings|
        allow(settings.dynamic_instrumentation).to receive(:enabled).and_return(true)
        allow(settings.dynamic_instrumentation.internal).to receive(:propagate_all_exceptions).and_return(false)
      end

      let(:serializer) do
        instance_double(Datadog::DI::Serializer)
      end

      let(:instrumenter) do
        Datadog::DI::Instrumenter.new(settings, serializer, logger)
      end

      let(:probe_notification_builder) do
        instance_double(Datadog::DI::ProbeNotificationBuilder)
      end

      let(:logger) do
        instance_double(Logger)
      end

      let(:probe_repository) do
        Datadog::DI::ProbeRepository.new
      end

      let(:probe_manager) do
        Datadog::DI::ProbeManager.new(settings, instrumenter, probe_notification_builder, probe_notifier_worker, logger, probe_repository)
      end

      let(:agent_settings) do
        instance_double_agent_settings
      end

      let(:transport) do
        instance_double(Datadog::DI::Transport)
      end

      let(:notifier_worker) do
        Datadog::DI::ProbeNotifierWorker.new(settings, agent_settings, transport)
      end

      let(:stringified_probe_spec) do
        JSON.parse(probe_spec.to_json)
      end

      let(:telemetry) do
        instance_double(Datadog::Core::Telemetry::Component)
      end

      before do
        expect(Datadog::DI).to receive(:component).at_least(:once).and_return(component)
      end

      context 'new probe received' do
        let(:probe_spec) do
          {id: '11', name: 'bar', type: 'LOG_PROBE', where: {typeName: 'Foo', methodName: 'bar'}}
        end

        let(:probe) { Datadog::DI::ProbeBuilder.build_from_remote_config(JSON.parse(probe_spec.to_json)) }

        before do
          # Uncomment for debugging:
          # allow(settings.dynamic_instrumentation.internal).to receive(:propagate_all_exceptions).and_return(true)
        end

        it 'calls probe manager to add a probe' do
          expect(component).to receive(:logger).and_return(logger)
          expect_lazy_log(logger, :debug, /received log probe/)

          expect(probe_manager).to receive(:add_probe) do |probe|
            expect(probe.id).to eq('11')
          end
          expect(component).to receive(:parse_probe_spec_and_notify).and_return(probe)
          receiver.call(repository, transaction)
        end

        context 'probe addition raises an exception' do
          it 'logs warning and consumes the exception' do
            expect(component).to receive(:telemetry).and_return(telemetry)
            expect(component).to receive(:logger).and_return(logger)
            expect_lazy_log(logger, :debug, /received log probe/)

            expect_lazy_log(logger, :debug, /unhandled exception.*Runtime error from test/)
            expect(component).to receive(:logger).and_return(logger)
            expect(telemetry).to receive(:report)

            expect(probe_manager).to receive(:add_probe).and_raise("Runtime error from test")
            expect(component).to receive(:parse_probe_spec_and_notify).and_return(probe)
            expect(component).to receive(:probe_notification_builder).and_return(probe_notification_builder)
            expect(probe_notification_builder).to receive(:build_errored)
            expect(component).to receive(:probe_notifier_worker).and_return(probe_notifier_worker)
            expect(probe_notifier_worker).to receive(:add_status)
            expect do
              receiver.call(repository, transaction)
            end.not_to raise_error
          end
        end
      end
    end
  end
end
