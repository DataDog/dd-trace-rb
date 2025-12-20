require 'spec_helper'
require 'datadog/di/spec_helper'

# This file contains tests for remote configuration behavior of DI, most
# importantly that when entries disappear from RC the corresponding probes
# are removed. The tests here exercise most of the RC machinery but only the
# DI Remote class - they do not run the rest of DI like the tests in the
# +integration+ subdirectory do.

RSpec.describe 'DI remote config' do
  di_test

  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |settings|
      settings.remote.enabled = true
      settings.dynamic_instrumentation.enabled = true
      settings.dynamic_instrumentation.internal.development = true
      settings.dynamic_instrumentation.internal.propagate_all_exceptions = true
    end
  end

  let(:transport) { double(Datadog::Core::Remote::Transport::Config) }
  let(:capabilities) { Datadog::Core::Remote::Client::Capabilities.new(settings, telemetry) }

  let(:logger) { logger_allowing_debug }

  let(:client) { Datadog::Core::Remote::Client.new(transport, capabilities, settings: settings, logger: logger) }

  let(:component) do
    # TODO should this use Component.new? We have to manually pass in
    # the code tracker in that case.
    Datadog::DI::Component.build(settings, agent_settings, logger).tap do |component|
      if component.nil?
        raise "Component failed to create - unsuitable environment? Check log entries"
      end
    end
  end

  after do
    component.shutdown!
  end

  let(:agent_settings) do
    instance_double_agent_settings_with_stubs
  end

  before do
    expect(Datadog::DI).to receive(:component).at_least(:once).and_return(component)
  end

  context 'when RC payload contains a probe definition' do
    let(:probe_configs) do
      {'datadog/2/LIVE_DEBUGGING/foo/bar' => probe_spec}
    end

    let(:response) do
      DIHelpers::TestRemoteConfigGenerator.new(probe_configs).mock_response
    end

    let(:probe_spec) do
      {id: '11', name: 'bar', type: 'LOG_PROBE', where: {typeName: 'Foo', methodName: 'bar'}}
    end

    let(:second_probe_spec) do
      {id: '12', name: 'bar', type: 'LOG_PROBE', where: {typeName: 'Foo', methodName: 'bar'}}
    end

    let(:probe) do
      double(Datadog::DI::Probe)
    end

    let(:response_two) do
      DIHelpers::TestRemoteConfigGenerator.new(probe_configs_two).mock_response
    end

    let(:second_probe) do
      double(Datadog::DI::Probe)
    end

    it 'adds the probe' do
      expect(transport).to receive(:send_config).and_return(response)

      expect(component).to receive(:parse_probe_spec_and_notify).and_return(probe)
      expect(component.probe_manager).to receive(:add_probe).with(probe)

      client.sync
    end

    context 'when the same payload is received twice' do
      it 'adds the probe only once' do
        expect(transport).to receive(:send_config).and_return(response)

        expect(component).to receive(:parse_probe_spec_and_notify).and_return(probe)
        expect(component.probe_manager).to receive(:add_probe).with(probe)

        client.sync

        expect(transport).to receive(:send_config).and_return(response)

        expect(component).not_to receive(:parse_probe_spec_and_notify)
        expect(component.probe_manager).not_to receive(:add_probe)

        client.sync
      end
    end

    context 'when the second response contains two probe definitions' do
      let(:probe_configs_two) do
        {
          'datadog/2/LIVE_DEBUGGING/foo/bar' => probe_spec,
          'datadog/2/LIVE_DEBUGGING/foo/bar2' => second_probe_spec,
        }
      end

      it 'adds the first probe only once and the second probe also once' do
        expect(transport).to receive(:send_config).and_return(response)

        expect(component).to receive(:parse_probe_spec_and_notify).and_return(probe)
        expect(component.probe_manager).to receive(:add_probe).with(probe)

        client.sync

        expect(transport).to receive(:send_config).and_return(response_two)

        expect(component).to receive(:parse_probe_spec_and_notify).and_return(second_probe)
        expect(component.probe_manager).to receive(:add_probe).with(second_probe)

        client.sync
      end
    end

    context 'when the second response contains one, different probe definition' do
      let(:probe_configs_two) do
        {
          'datadog/2/LIVE_DEBUGGING/foo/bar2' => second_probe_spec,
        }
      end

      it 'removes the first probe and adds the second probe' do
        expect(transport).to receive(:send_config).and_return(response)

        expect(component).to receive(:parse_probe_spec_and_notify).and_return(probe)
        expect(component.probe_manager).to receive(:add_probe).with(probe)

        client.sync

        expect(transport).to receive(:send_config).and_return(response_two)

        expect(component.probe_manager).to receive(:remove_probe).with(probe_spec.fetch(:id))
        expect(component).to receive(:parse_probe_spec_and_notify).and_return(second_probe)
        expect(component.probe_manager).to receive(:add_probe).with(second_probe)

        client.sync
      end
    end

    context 'when the second response contains zero probes' do
      let(:probe_configs_two) do
        {}
      end

      it 'removes the first probe' do
        expect(transport).to receive(:send_config).and_return(response)

        expect(component).to receive(:parse_probe_spec_and_notify).and_return(probe)
        expect(component.probe_manager).to receive(:add_probe).with(probe)

        client.sync

        expect(transport).to receive(:send_config).and_return(response_two)

        expect(component.probe_manager).to receive(:remove_probe).with(probe_spec.fetch(:id))

        client.sync
      end
    end

    context 'when the second response changes the first probe' do
      let(:probe_configs_two) do
        {
          'datadog/2/LIVE_DEBUGGING/foo/bar2' => modified_probe_spec,
        }
      end

      # Only some probe attributes can be changed in UI.
      # Location for example is not one of them.
      # Since we remove and re-instrument, we don't care which attributes
      # change, for now.
      let(:modified_probe_spec) do
        {id: '11', name: 'bar', type: 'LOG_PROBE', where: {typeName: 'Foo', methodName: 'different_bar'}}
      end

      it 'removes the first probe and instruments the updated spec' do
        expect(transport).to receive(:send_config).and_return(response)

        expect(component).to receive(:parse_probe_spec_and_notify).and_return(second_probe)
        expect(component.probe_manager).to receive(:add_probe).with(second_probe)

        client.sync

        expect(transport).to receive(:send_config).and_return(response_two)

        # Also assert that removal happens before reinstallation.
        expect(component.probe_manager).to receive(:remove_probe).with(probe_spec.fetch(:id)).ordered
        expect(component).to receive(:parse_probe_spec_and_notify).and_return(probe).ordered
        expect(component.probe_manager).to receive(:add_probe).with(probe).ordered

        client.sync
      end
    end
  end
end
