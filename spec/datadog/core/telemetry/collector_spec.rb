require 'spec_helper'

require 'datadog/core/environment/ext'
require 'datadog/core/environment/identity'
require 'datadog/core/telemetry/collector'
require 'datadog/core/telemetry/v1/integration'
require 'datadog/core/telemetry/v1/telemetry_request'
require 'datadog/core/telemetry/v1/app_started'
require 'ddtrace'
require 'rake'

RSpec.describe Datadog::Core::Telemetry::Collector do
  describe '::request' do
    subject(:request) { described_class.request(request_type) }
    let(:request_type) { 'app-started' }

    context('when :request_type') do
      context 'is app-started' do
        let(:request_type) { 'app-started' }

        around do |example|
          ClimateControl.modify(Datadog::Core::Environment::Ext::ENV_SERVICE => 'service-name') do
            example.run
          end
        end

        it { is_expected.to be_a_kind_of(Datadog::Core::Telemetry::V1::TelemetryRequest) }

        context('top-level keys') do
          before do
            allow(Time).to receive(:now).and_return(Time.new(2020))
          end

          it('api_version is set to default') { expect(request.api_version).to eq('v1') }

          it('request_type is set to app-started') { expect(request.request_type).to eq('app-started') }

          it('runtime_id is set correctly') { expect(request.runtime_id).to eq(Datadog::Core::Environment::Identity.id) }

          it('tracer_time is set correctly') { expect(request.tracer_time).to eq(Time.new(2020).to_i) }

          it('seq_id is incremented') do
            expect(described_class.request(request_type).seq_id).to eq(described_class.request(request_type).seq_id - 1)
          end
        end
      end

      context 'is invalid' do
        let(:request_type) { 'some-request-type' }
        it { expect { request }.to raise_error(ArgumentError) }
      end
    end
  end
end
