# frozen_string_literal: true

require "spec_helper"
require "timeout"
require "datadog/open_feature/activation"
require "datadog/open_feature/provider"

RSpec.describe Datadog::OpenFeature::Provider, "configuration delivery lifecycle" do
  let(:provider) { described_class.new }
  let(:configuration) { ::OpenFeature::SDK::Configuration.new }
  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |config|
      config.feature_flags.configuration_source = "remote_config"
      config.feature_flags.initialization_timeout_ms = 30_000
      config.open_feature.evaluation_counts_enabled = false
      config.remote.enabled = true
    end
  end
  let(:agent_settings) { Datadog::Core::Configuration::AgentSettingsResolver.call(settings) }
  let(:remote) { instance_double(Datadog::Core::Remote::Component, register: nil, start: nil) }
  let(:logger) { instance_double(Datadog::Core::Logger, error: nil, warn: nil, debug: nil, debug?: false) }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component, report: nil) }
  let(:activation) do
    Datadog::OpenFeature::Activation.new(settings, agent_settings, remote, logger: logger, telemetry: telemetry)
  end
  let(:component) { activation.activate(provider) }
  let(:flags) do
    '{"id":"1","createdAt":"2024-04-17T19:40:53.716Z","format":"SERVER",' \
      '"environment":{"name":"test"},"flags":{}}'
  end
  let(:events) { [] }

  before do
    allow(Datadog::OpenFeature).to receive(:activate_provider).with(provider) do
      [activation.activate(provider), activation.failure]
    end
    allow(Datadog::OpenFeature).to receive(:deactivate_provider).with(provider) { activation.deactivate(provider) }
    configuration.add_handler(::OpenFeature::SDK::ProviderEvent::PROVIDER_READY, ->(_) { events << :ready })
  end

  after do
    provider.shutdown
    activation.shutdown!
    configuration.send(:reset)
  end

  describe "fork recovery" do
    before { skip "Fork not supported" unless Process.respond_to?(:fork) }

    [false, true].each do |cached|
      it "recovers an abandoned initializer with configuration #{cached ? "cached before" : "received after"} the fork hook" do
        waiting = Queue.new
        allow(component).to receive(:wait_for_configuration).and_wrap_original do |method, &cancelled|
          waiting << true
          method.call(&cancelled)
        end
        initialization = Thread.new { configuration.set_provider_and_wait(provider) }
        Timeout.timeout(5) { waiting.pop }

        expect_in_fork do
          expect(initialization).not_to be_alive
          component.reconfigure!(flags) if cached

          activation.after_fork
          component.reconfigure!(flags) unless cached

          expect(component).to be_configuration_received
          expect(configuration.send(:provider_state, provider)).to eq(::OpenFeature::SDK::ProviderState::READY)
          expect(events).to eq([:ready])
          activation.after_fork
          expect(events).to eq([:ready])
        end

        component.reconfigure!(flags)
        expect(initialization.join(5)).to eq(initialization)
        initialization.value
        expect(events).to eq([:ready])
      ensure
        initialization&.kill
        initialization&.join(5)
      end
    end

    it "leaves initialization on the forking thread to complete normally" do
      allow(component).to receive(:wait_for_configuration).and_wrap_original do |method, &cancelled|
        expect_in_fork do
          activation.after_fork
          component.reconfigure!(flags)

          expect(events).to be_empty
          expect(configuration.send(:provider_state, provider)).to eq(::OpenFeature::SDK::ProviderState::NOT_READY)
        end
        component.reconfigure!(flags)
        method.call(&cancelled)
      end

      configuration.set_provider_and_wait(provider)

      expect(events).to eq([:ready])
    end

    it "preserves the live initializer until the SDK delivers its READY event" do
      component.reconfigure!(flags)
      first_ready = true
      allow(configuration).to receive(:dispatch_provider_event).and_wrap_original do |method, event_provider, event, *args|
        if event == ::OpenFeature::SDK::ProviderEvent::PROVIDER_READY && first_ready
          first_ready = false
          expect_in_fork do
            activation.after_fork

            expect(events).to be_empty
            expect(configuration.send(:provider_state, provider)).to eq(::OpenFeature::SDK::ProviderState::NOT_READY)
          end
        end
        method.call(event_provider, event, *args)
      end

      configuration.set_provider_and_wait(provider)

      expect(events).to eq([:ready])
    end

    it "does not emit another READY for an initialized provider" do
      component.reconfigure!(flags)
      configuration.set_provider_and_wait(provider)

      expect_in_fork do
        activation.after_fork

        expect(events).to eq([:ready])
        expect(configuration.send(:provider_state, provider)).to eq(::OpenFeature::SDK::ProviderState::READY)
      end
    end
  end

  describe "component replacement during initialization" do
    let(:replacement) do
      Datadog::OpenFeature::Activation.new(settings, agent_settings, remote, logger: logger, telemetry: telemetry)
    end

    after { replacement.shutdown! }

    [[:ready], [:ready, :lost], [:ready, :lost, :ready]].each do |sequence|
      it "preserves replacement state after #{sequence.join("/")}" do
        waiting = Queue.new
        wait_finished = Queue.new
        finish_initialization = Queue.new
        allow(component).to receive(:wait_for_configuration).and_wrap_original do |method, &cancelled|
          waiting << true
          result = method.call(&cancelled)
          wait_finished << result
          finish_initialization.pop
          result
        end
        initialization = Thread.new do
          configuration.set_provider_and_wait(provider)
        rescue ::OpenFeature::SDK::ProviderInitializationError => error
          error
        end
        Timeout.timeout(5) { waiting.pop }

        activation.shutdown!
        expect(Timeout.timeout(5) { wait_finished.pop }).to eq(:shutdown)
        replacement_component = replacement.activate(provider)
        sequence.each { |event| replacement_component.reconfigure!((event == :ready) ? flags : nil) }
        finish_initialization << true

        expect(initialization.join(5)).to eq(initialization)
        expect(initialization.value).to be_a(::OpenFeature::SDK::ProviderInitializationError)
        expected_state = (sequence.last == :ready) ? ::OpenFeature::SDK::ProviderState::READY : ::OpenFeature::SDK::ProviderState::ERROR
        expect(configuration.send(:provider_state, provider)).to eq(expected_state)
        expect(events).to eq((sequence.last == :ready) ? [:ready] : [])
      ensure
        initialization&.kill
        initialization&.join(5)
      end
    end
  end

  it "recovers after another provider retries a failed activation and preserves the original exception" do
    error = IOError.new("Remote Configuration startup failed")
    allow(remote).to receive(:start).and_raise(error)

    expect { configuration.set_provider_and_wait(provider) }
      .to raise_error(::OpenFeature::SDK::ProviderInitializationError) { |failure| expect(failure.original_error).to be(error) }
    expect(configuration.send(:provider_state, provider)).to eq(::OpenFeature::SDK::ProviderState::ERROR)

    allow(remote).to receive(:start).and_return(nil)
    second_provider = described_class.new
    recovered_component = activation.activate(second_provider)
    recovered_component.reconfigure!(flags)

    expect(configuration.send(:provider_state, provider)).to eq(::OpenFeature::SDK::ProviderState::READY)
    expect(events).to eq([:ready])
  ensure
    activation.deactivate(second_provider) if second_provider
  end

  context "with a real Remote Configuration worker" do
    let(:remote) do
      Datadog::Core::Remote::Component.build(settings, agent_settings, logger: logger, telemetry: telemetry)
    end

    before do
      skip "Fork not supported" unless Process.respond_to?(:fork)
      allow_any_instance_of(Datadog::Core::Remote::Negotiation).to receive(:endpoint?).and_return(false)
    end

    after { remote.shutdown! }

    it "restarts polling in a child without requiring a request" do
      activation.start!
      original_client_id = remote.client.id
      expect(remote).to be_started

      expect_in_fork do
        remote.after_fork
        expect(remote).not_to be_started

        activation.after_fork

        expect(remote).to be_started
        expect(remote.client.id).not_to eq(original_client_id)
        remote.shutdown!
      end

      expect(remote).to be_started
      expect(remote.client.id).to eq(original_client_id)
    end
  end
end
