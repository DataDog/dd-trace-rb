require 'ddtrace/contrib/rails/rails_helper'

RSpec.describe 'Rails defaults' do
  include_context 'Rails test application'

  context 'when Datadog.configuration.service' do
    before do
      Datadog.configure { |c| c.service = default_service }
      app
    end

    after { Datadog.configure { |c| c.service = nil } }

    context 'is not configured' do
      let(:default_service) { nil }

      describe 'Datadog.configuration.service' do
        subject(:global_default_service) { Datadog.configuration.service }
        it { expect(global_default_service).to match(/rails/) }
      end

      describe 'Tracer#default_service' do
        subject(:tracer_default_service) { Datadog.configuration[:rails].tracer.default_service }
        it { expect(tracer_default_service).to match(/rails/) }
      end

      describe 'Rails :service_name' do
        subject(:rails_service_name) { Datadog.configuration[:rails].service_name }
        it { expect(rails_service_name).to match(/rails/) }
      end
    end

    context 'is configured' do
      let(:default_service) { 'default-service' }

      describe 'Datadog.configuration.service' do
        subject(:global_default_service) { Datadog.configuration.service }
        it { expect(global_default_service).to be default_service }
      end

      describe 'Tracer#default_service' do
        subject(:tracer_default_service) { Datadog.configuration[:rails].tracer.default_service }
        it { expect(tracer_default_service).to eq(default_service) }
      end

      describe 'Rails :service_name' do
        subject(:rails_service_name) { Datadog.configuration[:rails].service_name }
        it { expect(rails_service_name).to eq(default_service) }
      end
    end
  end
end
