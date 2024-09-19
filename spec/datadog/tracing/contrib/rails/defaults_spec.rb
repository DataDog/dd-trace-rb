require 'datadog/tracing/contrib/rails/rails_helper'

RSpec.describe 'Rails defaults' do
  include_context 'Rails test application'

  context 'when Datadog.configuration.service' do
    after { without_warnings { Datadog.configuration.reset! } }

    context 'is not configured' do
      before { app }

      describe 'Datadog.configuration.service' do
        subject(:global_default_service) { Datadog.configuration.service }

        it { expect(global_default_service).to start_with('rails') }
      end

      describe 'Global tracer default_service' do
        subject(:tracer_default_service) { Datadog::Tracing.send(:tracer).default_service }

        it { expect(tracer_default_service).to start_with('rails') }
      end
    end

    context 'is configured' do
      before do
        Datadog.configure { |c| c.service = 'default-service' }
        app
      end

      describe 'Datadog.configuration.service' do
        subject(:global_default_service) { Datadog.configuration.service }

        it { expect(global_default_service).to eq('default-service') }
      end

      describe 'Global tracer default_service' do
        subject(:tracer_default_service) { Datadog::Tracing.send(:tracer).default_service }

        it { expect(tracer_default_service).to eq('default-service') }
      end
    end
  end
end
