require 'spec_helper'

require 'datadog/core/configuration'
require 'datadog/core/configuration/agent_settings_resolver'
require 'datadog/core/environment/ext'
require 'datadog/core/telemetry/collector'
require 'datadog/core/telemetry/v1/application'
require 'datadog/core/telemetry/v1/dependency'
require 'datadog/core/telemetry/v1/host'
require 'datadog/core/telemetry/v1/integration'
require 'datadog/core/telemetry/v1/product'
require 'datadog/core/transport/ext'
require 'datadog/profiling/profiler'

require 'datadog'
require 'datadog/version'

RSpec.describe Datadog::Core::Telemetry::Collector do
  let(:dummy_class) { Class.new { extend(Datadog::Core::Telemetry::Collector) } }

  before do
    # We don't care about details of profiling initialization (which requires
    # interacting with native extension) in this suite. This initialization is
    # tested in other suites. Thus, mock it to nil throughout.
    # NOTE: We could have used a double but that leads to messy configuration
    # lifecycle as we'd need to do a full reconfiguration in an `after` block
    # (which would require extra allow/expect for unrelated things). The global
    # reset with `around` happens already outside of a test context where it is
    # forbidden to interact with doubles (and thus we can't call shutdown! on it)
    allow(Datadog::Profiling::Component).to receive(:build_profiler_component).and_return(nil)
  end

  describe '#application' do
    subject(:application) { dummy_class.application }
    let(:env_service) { 'default-service' }

    around do |example|
      ClimateControl.modify(Datadog::Core::Environment::Ext::ENV_SERVICE => env_service) do
        example.run
      end
    end

    it { is_expected.to be_a_kind_of(Datadog::Core::Telemetry::V1::Application) }

    describe ':env' do
      subject(:env) { application.env }

      context 'when DD_ENV not set' do
        it { is_expected.to be_nil }
      end

      context 'when DD_env set' do
        around do |example|
          ClimateControl.modify(Datadog::Core::Environment::Ext::ENV_ENVIRONMENT => 'test_env') do
            example.run
          end
        end

        it { is_expected.to be_a_kind_of(String) }
        it('reads value correctly') { is_expected.to eql('test_env') }
      end
    end

    describe ':service_name' do
      subject(:service_name) { application.service_name }
      let(:env_service) { 'test-service' }

      it { is_expected.to be_a_kind_of(String) }
      it('reads value correctly') { is_expected.to eql('test-service') }
    end

    describe ':service_version' do
      subject(:service_version) { application.service_version }

      context 'when DD_VERSION not set' do
        it { is_expected.to be_nil }
      end

      context 'when DD_VERSION set' do
        around do |example|
          ClimateControl.modify(Datadog::Core::Environment::Ext::ENV_VERSION => '4.2.0') do
            example.run
          end
        end

        it { is_expected.to be_a_kind_of(String) }
        it('reads value correctly') { is_expected.to eql('4.2.0') }
      end
    end

    describe ':products' do
      subject(:products) { application.products }

      context 'when profiling and appsec are disabled' do
        before do
          Datadog.configuration.profiling.enabled = false
          Datadog.configuration.appsec.enabled = false
          stub_const('Datadog::Core::Environment::Ext::GEM_DATADOG_VERSION', '4.2')
        end

        after do
          Datadog.configuration.reset!
        end

        it { expect(products.appsec).to eq({ version: '4.2' }) }
        it { expect(products.profiler).to eq({ version: '4.2' }) }
      end

      context 'when both profiler and appsec are enabled' do
        require 'datadog/appsec'

        before do
          Datadog.configure do |c|
            c.profiling.enabled = true
            c.appsec.enabled = true
          end
        end

        after do
          Datadog.configuration.reset!
        end

        it { is_expected.to be_a_kind_of(Datadog::Core::Telemetry::V1::Product) }
        it { expect(products.appsec).to be_a_kind_of(Hash) }
        it { expect(products.profiler).to be_a_kind_of(Hash) }
      end
    end
  end

  describe '#configurations' do
    subject(:configurations) { dummy_class.configurations }

    it { is_expected.to be_a_kind_of(Hash) }
    it { expect(configurations.values).to_not include(nil) }
    it { expect(configurations.values).to_not include({}) }

    context 'DD_AGENT_HOST' do
      let(:dd_agent_host) { 'ddagent' }

      context 'when set via configuration' do
        before do
          Datadog.configure do |c|
            c.agent.host = dd_agent_host
          end
        end

        it { is_expected.to include(:DD_AGENT_HOST => dd_agent_host) }
      end

      context 'when no value set' do
        let(:dd_agent_host) { nil }
        it { is_expected.to_not include(:DD_AGENT_HOST) }
      end
    end

    context 'DD_AGENT_TRANSPORT' do
      context 'when no configuration variables set' do
        it { is_expected.to include(:DD_AGENT_TRANSPORT => 'TCP') }
      end

      context 'when adapter is type :unix' do
        let(:adapter_type) { Datadog::Core::Transport::Ext::UnixSocket::ADAPTER }

        before do
          allow(Datadog::Core::Configuration::AgentSettingsResolver)
            .to receive(:call).and_return(double('agent settings', :adapter => adapter_type))
        end
        it { is_expected.to include(:DD_AGENT_TRANSPORT => 'UDS') }
      end
    end

    context 'DD_TRACE_SAMPLE_RATE' do
      around do |example|
        ClimateControl.modify DD_TRACE_SAMPLE_RATE: dd_trace_sample_rate do
          example.run
        end
      end

      let(:dd_trace_sample_rate) { nil }
      context 'when set' do
        let(:dd_trace_sample_rate) { '0.2' }
        it { is_expected.to include(:DD_TRACE_SAMPLE_RATE => '0.2') }
      end

      context 'when nil' do
        let(:dd_trace_sample_rate) { nil }
        it { is_expected.to_not include(:DD_TRACE_SAMPLE_RATE) }
      end
    end

    context 'DD_TRACE_REMOVE_INTEGRATION_SERVICE_NAMES_ENABLED' do
      around do |example|
        ClimateControl.modify(
          DD_TRACE_REMOVE_INTEGRATION_SERVICE_NAMES_ENABLED: dd_trace_remove_integration_service_names_enabled
        ) do
          example.run
        end
      end

      context 'when set to true' do
        let(:dd_trace_remove_integration_service_names_enabled) { 'true' }
        it { is_expected.to include(:DD_TRACE_REMOVE_INTEGRATION_SERVICE_NAMES_ENABLED => true) }
      end

      context 'when nil defaults to false' do
        let(:dd_trace_remove_integration_service_names_enabled) { nil }
        it { is_expected.to include(:DD_TRACE_REMOVE_INTEGRATION_SERVICE_NAMES_ENABLED => false) }
      end
    end

    context 'DD_TRACE_PEER_SERVICE_MAPPING' do
      around do |example|
        ClimateControl.modify(
          DD_TRACE_PEER_SERVICE_MAPPING: dd_trace_peer_service_mapping
        ) do
          example.run
        end
      end

      context 'when set' do
        let(:dd_trace_peer_service_mapping) { 'key:value' }
        it { is_expected.to include(:DD_TRACE_PEER_SERVICE_MAPPING => 'key:value') }
      end

      context 'when nil is blank' do
        let(:dd_trace_peer_service_mapping) { nil }
        it { is_expected.to include(:DD_TRACE_PEER_SERVICE_MAPPING => '') }
      end
    end
  end

  describe '#additional_payload' do
    subject(:additional_payload) { dummy_class.additional_payload }

    it { is_expected.to be_a_kind_of(Hash) }
    it { expect(additional_payload.values).to_not include(nil) }
    it { expect(additional_payload.values).to_not include({}) }

    context 'when environment variable configuration' do
      let(:dd_tracing_analytics_enabled) { 'true' }
      around do |example|
        ClimateControl.modify DD_TRACE_ANALYTICS_ENABLED: dd_tracing_analytics_enabled do
          example.run
        end
      end

      context 'is set' do
        let(:dd_tracing_analytics_enabled) { 'true' }
        it do
          is_expected.to include(
            'tracing.analytics.enabled' => true
          )
        end
      end

      context 'is nil' do
        let(:dd_tracing_analytics_enabled) { nil }
        it { is_expected.to_not include('tracing.analytics.enabled') }
      end
    end

    context 'when profiling is disabled' do
      before do
        Datadog.configuration.profiling.enabled = false
        Datadog.configuration.appsec.enabled = false
      end
      after do
        Datadog.configuration.reset!
      end
      it { is_expected.to include('profiling.enabled' => false) }
    end

    context 'when profiling is enabled' do
      before do
        stub_const('Datadog::Core::Environment::Ext::GEM_DATADOG_VERSION', '4.2')
        Datadog.configure do |c|
          c.profiling.enabled = true
        end
      end
      after { Datadog.configuration.profiling.send(:reset!) }

      it { is_expected.to include('profiling.enabled' => true) }
    end

    context 'when appsec is enabled' do
      before do
        require 'datadog/appsec'

        stub_const('Datadog::Core::Environment::Ext::GEM_DATADOG_VERSION', '4.2')
        Datadog.configure do |c|
          c.appsec.enabled = true
        end
      end
      after { Datadog.configuration.reset! }

      it { is_expected.to include('appsec.enabled' => true) }
    end

    context 'when ci is not loaded' do
      it { is_expected.not_to include('ci.enabled') }
    end

    context 'when ci is enabled' do
      around do |example|
        Datadog.configuration.define_singleton_method(:ci) do
          OpenStruct.new(enabled: true)
        end
        example.run
        class << Datadog.configuration
          remove_method(:ci)
        end
      end

      it { is_expected.to include('ci.enabled' => true) }
    end

    context 'when ci is not enabled' do
      around do |example|
        Datadog.configuration.define_singleton_method(:ci) do
          OpenStruct.new(enabled: false)
        end
        example.run
        class << Datadog.configuration
          remove_method(:ci)
        end
      end

      it { is_expected.to include('ci.enabled' => false) }
    end

    context 'when OpenTelemetry is enabled' do
      before do
        stub_const('Datadog::OpenTelemetry::LOADED', true)
      end

      it { is_expected.to include('tracing.opentelemetry.enabled' => true) }
    end
  end

  describe '#dependencies' do
    subject(:dependencies) { dummy_class.dependencies }

    it { is_expected.to be_a_kind_of(Array) }
    it { is_expected.to all(be_a(Datadog::Core::Telemetry::V1::Dependency)) }
  end

  describe '#host' do
    subject(:host) { dummy_class.host }

    it { is_expected.to be_a_kind_of(Datadog::Core::Telemetry::V1::Host) }
  end

  describe '#install_signature' do
    subject(:install_signature) { dummy_class.install_signature }

    it { is_expected.to be_a_kind_of(Datadog::Core::Telemetry::V1::InstallSignature) }

    describe ':install_id' do
      subject(:install_id) { install_signature.install_id }

      context 'when DD_INSTRUMENTATION_INSTALL_ID not set' do
        it('is nil when unset') { is_expected.to be_nil }
      end

      context 'when DD_INSTRUMENTATION_INSTALL_ID set' do
        let(:install_id) { '68e75c48-57ca-4a12-adfc-575c4b05fcbe' }

        before do
          Datadog.configure do |c|
            c.telemetry.install_id = install_id
          end
        end
        after do
          Datadog.configuration.reset!
        end

        it { is_expected.to eql(install_id) }
      end
    end

    describe ':install_type' do
      subject(:install_type) { install_signature.install_type }

      context 'when DD_INSTRUMENTATION_INSTALL_TYPE not set' do
        it('is nil when unset') { is_expected.to be_nil }
      end

      context 'when DD_INSTRUMENTATION_INSTALL_TYPE set' do
        before do
          Datadog.configure do |c|
            c.telemetry.install_type = install_type
          end
        end
        after do
          Datadog.configuration.reset!
        end

        it { is_expected.to eql(install_type) }
      end
    end

    describe ':install_time' do
      subject(:install_time) { install_signature.install_time }

      context 'when DD_INSTRUMENTATION_INSTALL_TIME not set' do
        it('is nil when unset') { is_expected.to be_nil }
      end

      context 'when DD_INSTRUMENTATION_INSTALL_TIME set' do
        before do
          Datadog.configure do |c|
            c.telemetry.install_time = install_time
          end
        end
        after do
          Datadog.configuration.reset!
        end

        it { is_expected.to eql(install_time) }
      end
    end
  end

  describe '#integrations' do
    subject(:integrations) { dummy_class.integrations }

    it { is_expected.to be_a_kind_of(Array) }
    it { is_expected.to all(be_a(Datadog::Core::Telemetry::V1::Integration)) }
    it('contains list of all integrations') { expect(integrations.length).to eq(Datadog.registry.entries.length) }

    context 'when a configure block is called' do
      around do |example|
        Datadog.registry[:rake].reset_configuration!
        Datadog.registry[:pg].reset_configuration!
        example.run
        Datadog.registry[:rake].reset_configuration!
        Datadog.registry[:pg].reset_configuration!
      end
      before do
        require 'rake'
        Datadog.configure do |c|
          c.tracing.instrument :rake
          c.tracing.instrument :pg
        end
      end

      it 'sets integration as enabled' do
        expect(integrations).to include(
          an_object_having_attributes(name: 'rake', enabled: true, compatible: true)
        )
      end

      it 'propogates errors with configuration' do
        expect(integrations)
          .to include(
            an_object_having_attributes(
              name: 'pg',
              enabled: false,
              compatible: false,
              error: 'Available?: false, Loaded? false, Compatible? false, Patchable? false'
            )
          )
      end
    end

    context 'when error is raised in patching' do
      let(:error) { instance_double('error', class: StandardError, message: nil, backtrace: []) }
      before do
        Datadog::Tracing::Contrib::Redis::Patcher.on_patch_error(error)
        Datadog.configure do |c|
          c.tracing.instrument :redis
        end
      end
      after { Datadog::Tracing::Contrib::Redis::Patcher.patch_error_result = nil }
      around do |example|
        Datadog.registry[:redis].reset_configuration!
        example.run
        Datadog.registry[:redis].reset_configuration!
      end
      it do
        expect(integrations)
          .to include(
            an_object_having_attributes(
              name: 'redis',
              enabled: false,
              compatible: false,
              error: { type: 'StandardError' }.to_s
            )
          )
      end
    end
  end

  describe '#runtime_id' do
    subject(:runtime_id) { dummy_class.runtime_id }

    it { is_expected.to be_a_kind_of(String) }

    context 'when invoked twice' do
      it { is_expected.to eq(runtime_id) }
    end
  end

  describe '#tracer_time' do
    subject(:tracer_time) { dummy_class.tracer_time }

    before do
      allow(Time).to receive(:now).and_return(Time.at(1577836800))
    end

    it { is_expected.to be_a_kind_of(Integer) }
    it('captures time with Time.now') { is_expected.to eq(1577836800) }
  end
end
