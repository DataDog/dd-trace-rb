require 'spec_helper'

require 'datadog/appsec'
require 'datadog/core/configuration'
require 'datadog/core/environment/ext'
require 'datadog/core/telemetry/collector'
require 'datadog/core/telemetry/v1/application'
require 'datadog/core/telemetry/v1/appsec'
require 'datadog/core/telemetry/v1/configuration'
require 'datadog/core/telemetry/v1/dependency'
require 'datadog/core/telemetry/v1/host'
require 'datadog/core/telemetry/v1/integration'
require 'datadog/core/telemetry/v1/product'
require 'datadog/core/telemetry/v1/profiler'

require 'ddtrace'
require 'ddtrace/version'

RSpec.describe Datadog::Core::Telemetry::Collector do
  let(:dummy_class) { Class.new { extend(Datadog::Core::Telemetry::Collector) } }

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
        it('reads value correctly') { is_expected.to eql('test_env') }
      end
    end

    describe ':service_name' do
      subject(:service_name) { application.service_name }
      let(:env_service) { 'test-service' }
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
        it('reads value correctly') { is_expected.to eql('4.2.0') }
      end
    end

    describe ':products' do
      subject(:products) { application.products }

      context 'when profiling and appsec are disabled' do
        before do
          Datadog.configuration.profiling.enabled = false
          Datadog.configuration.appsec.enabled = false
        end
        after do
          Datadog.configuration.profiling.send(:reset!)
          Datadog.configuration.appsec.send(:reset!)
        end
        it { is_expected.to be_nil }
      end

      context 'when profiling is enabled' do
        before do
          stub_const('Datadog::Core::Environment::Ext::TRACER_VERSION', '4.2')
          Datadog.configure do |c|
            c.profiling.enabled = true
          end
        end
        after { Datadog.configuration.profiling.send(:reset!) }

        it { is_expected.to be_a_kind_of(Datadog::Core::Telemetry::V1::Product) }
        it { expect(products.profiler).to be_a_kind_of(Datadog::Core::Telemetry::V1::Profiler) }
        it { expect(products.profiler).to have_attributes(version: '4.2') }
      end

      context 'when appsec is enabled' do
        before do
          stub_const('Datadog::Core::Environment::Ext::TRACER_VERSION', '4.2')
          Datadog.configure do |c|
            c.appsec.enabled = true
          end
        end
        after { Datadog.configuration.appsec.send(:reset!) }

        it { is_expected.to be_a_kind_of(Datadog::Core::Telemetry::V1::Product) }
        it { expect(products.appsec).to be_a_kind_of(Datadog::Core::Telemetry::V1::AppSec) }
        it { expect(products.appsec).to have_attributes(version: '4.2') }
      end

      context 'when both profiler and appsec are enabled' do
        before do
          Datadog.configure do |c|
            c.profiling.enabled = true
            c.appsec.enabled = true
          end
        end
        after do
          Datadog.configuration.profiling.send(:reset!)
          Datadog.configuration.appsec.send(:reset!)
        end

        it { is_expected.to be_a_kind_of(Datadog::Core::Telemetry::V1::Product) }
        it { expect(products.profiler).to be_a_kind_of(Datadog::Core::Telemetry::V1::Profiler) }
        it { expect(products.appsec).to be_a_kind_of(Datadog::Core::Telemetry::V1::AppSec) }
      end
    end
  end

  describe '#configurations' do
    subject(:configurations) { dummy_class.configurations }

    it { is_expected.to be_a_kind_of(Array) }
    it { is_expected.to all(be_a(Datadog::Core::Telemetry::V1::Configuration)) }
    it { is_expected.to_not include(an_object_having_attributes(:value => nil)) }
    it { is_expected.to_not include(an_object_having_attributes(:value => {})) }

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
          is_expected.to include(an_object_having_attributes(:name => 'tracing.analytics.enabled',
                                                             :value => true))
        end
      end

      context 'is nil' do
        let(:dd_tracing_analytics_enabled) { nil }
        it { is_expected.to_not include(an_object_having_attributes(:name => 'tracing.analytics.enabled')) }
      end
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
        expect(integrations)
          .to include(an_object_having_attributes(
                        name: 'rake',
                        enabled: true,
                        compatible: true,
                        error: nil
                      ))
      end

      it 'propogates errors with configuration' do
        expect(integrations)
          .to include(an_object_having_attributes(
                        name: 'pg',
                        enabled: false,
                        compatible: false,
                        error: 'Available?: false, Loaded? false, Compatible? false, Patchable? false'
                      ))
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
      allow(Time).to receive(:now).and_return(Time.new(2020))
    end

    it { is_expected.to be_a_kind_of(Integer) }
    it('captures time with Time.now') { is_expected.to eq(1577836800) }
  end
end
