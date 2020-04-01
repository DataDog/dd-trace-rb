require 'ddtrace/contrib/rails/rails_helper'

RSpec.describe 'Rails defaults' do
  include_context 'Rails test application'

  context 'when Datadog.configuration.service' do
    before do
      Datadog.configuration.service = default_service
      app
    end

    after { Datadog.configuration.service = nil }

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

  context 'when Datadog.configuration.env' do
    before do
      skip('Rails#env is not defined.') unless Rails.respond_to?(:env)
      Datadog.configuration.env = default_env
      app
    end

    after { Datadog.configuration.env = nil }

    context 'is not configured' do
      let(:default_env) { nil }

      describe 'Datadog.configuration.env' do
        subject(:global_default_env) { Datadog.configuration.env }
        it { expect(global_default_env).to eq Rails.env }
      end

      describe 'Tracer#tags' do
        subject(:tracer_tags) { Datadog.configuration[:rails].tracer.tags }
        it { expect(tracer_tags).to include('env' => Rails.env) }
      end
    end

    context 'is configured' do
      let(:default_env) { 'default-env' }

      describe 'Datadog.configuration.env' do
        subject(:global_default_env) { Datadog.configuration.env }
        it { expect(global_default_env).to eq default_env }
      end

      describe 'Tracer#tags' do
        subject(:tracer_tags) { Datadog.configuration[:rails].tracer.tags }
        it { expect(tracer_tags).to include('env' => default_env) }
      end
    end
  end
end
