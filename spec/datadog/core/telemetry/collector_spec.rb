require 'spec_helper'

require 'ddtrace/version'
require 'datadog/core/environment/ext'
require 'datadog/core/environment/identity'
require 'datadog/core/telemetry/collector'
require 'datadog/core/telemetry/v1/configuration'
require 'datadog/core/telemetry/v1/integration'
require 'datadog/core/telemetry/v1/telemetry_request'
require 'datadog/core/telemetry/v1/app_started'
require 'ddtrace'
require 'rake'

RSpec.describe Datadog::Core::Telemetry::Collector do
  describe '::request' do
    subject(:request) { described_class.request(request_type) }
    let(:request_type) { 'app-started' }

    # we need to ensure the service is set
    around do |example|
      ClimateControl.modify(Datadog::Core::Environment::Ext::ENV_SERVICE => 'service') do
        example.run
      end
    end

    context('when :request_type') do
      context 'is app-started' do
        let(:request_type) { 'app-started' }

        it { is_expected.to be_a_kind_of(Datadog::Core::Telemetry::V1::TelemetryRequest) }

        context('top-level keys') do
          before do
            allow(Time).to receive(:now).and_return(Time.new(2020))
          end
          it('api_version is set to default v1') { expect(request.api_version).to eq('v1') }

          it('request_type is set to app-started') { expect(request.request_type).to eq('app-started') }

          it('runtime_id is set correctly') { expect(request.runtime_id).to eq(Datadog::Core::Environment::Identity.id) }

          it('tracer_time is set correctly') { expect(request.tracer_time).to eq(1577836800) }

          it('seq_id is incremented') do
            expect(described_class.request(request_type).seq_id).to eq(described_class.request(request_type).seq_id - 1)
          end
        end

        context('payload') do
          let(:payload) { request.payload }
          around do |example|
            ClimateControl.modify DD_SERVICE: 'my-test-service' do
              example.run
            end
          end
          it 'configuration is set via environment variables' do
            expect(payload.configuration)
              .to include(an_object_having_attributes(name: 'DD_SERVICE', value: 'my-test-service'))
          end

          context 'integrations' do
            let(:integrations) { payload.integrations }

            it('contains list of all integrations') { expect(integrations.length).to eq(Datadog.registry.entries.length) }

            context 'after a configure block is called' do
              around do |example|
                Datadog.registry[:rake].reset_configuration!
                Datadog.registry[:pg].reset_configuration!
                example.run
                Datadog.registry[:rake].reset_configuration!
                Datadog.registry[:pg].reset_configuration!
              end
              before do
                Datadog.configure do |c|
                  c.tracing.instrument :rake
                  c.tracing.instrument :pg
                end
              end

              it 'sets integration as enabled' do
                expect(integrations).to include(an_object_having_attributes(
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

          context 'application' do
            let(:application) { request.application }

            context 'products' do
              let(:products) { application.products }

              context 'when no products enabled' do
                it { expect(request).not_to respond_to(:products) }
              end

              context 'when profiling is enabled' do
                before do
                  stub_const('Datadog::Core::Environment::Ext::TRACER_VERSION', '4.2')
                  Datadog.configure do |c|
                    c.profiling.enabled = true
                  end
                end

                it { expect(products).to respond_to(:profiler) }

                it('profiler product has same version as tracer') do
                  expect(products.profiler).to have_attributes(version: '4.2')
                end
              end
            end
          end
        end
      end

      context 'is nil' do
        let(:request_type) { nil }
        it { expect { request }.to raise_error(ArgumentError) }
      end

      context 'is invalid option' do
        let(:request_type) { 'some-request-type' }
        it { expect { request }.to raise_error(ArgumentError) }
      end
    end

    context('when :api_version') do
      subject(:request) { described_class.request(request_type, api_version) }
      let(:request_type) { 'app-started' }
      let(:api_version) { 'v1' }

      it { is_expected.to be_a_kind_of(Datadog::Core::Telemetry::V1::TelemetryRequest) }

      context 'is valid version' do
        let(:api_version) { 'v1' }
        it { expect(request.api_version).to eq('v1') }
      end

      context 'is not a valid version' do
        let(:api_version) { 'v2' }
        it { expect { request }.to raise_error(ArgumentError) }
      end
    end
  end
end
