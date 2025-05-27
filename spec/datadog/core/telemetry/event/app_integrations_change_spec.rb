require 'spec_helper'

require 'datadog/core/telemetry/event/app_integrations_change'

RSpec.describe Datadog::Core::Telemetry::Event::AppIntegrationsChange do
  let(:id) { double('seq_id') }
  let(:event) { described_class.new }

  subject(:payload) { event.payload }

  it_behaves_like 'telemetry event with no attributes'

  it 'all have name and compatibility' do
    is_expected.to match(integrations: all(include(name: kind_of(String), compatible: boolean)))
  end

  context 'with an instrumented integration' do
    context 'that applied' do
      before do
        Datadog.configure do |c|
          c.tracing.instrument :http
        end
      end
      it 'has a list of integrations' do
        is_expected.to match(
          integrations: include(
            name: 'http',
            version: RUBY_VERSION,
            compatible: true,
            enabled: true
          )
        )
      end
    end

    context 'that failed to apply' do
      before do
        raise 'pg is loaded! This test requires integration that does not have its gem loaded' if Gem.loaded_specs['pg']

        Datadog.configure do |c|
          c.tracing.instrument :pg
        end
      end

      it 'has a list of integrations' do
        is_expected.to match(
          integrations: include(
            name: 'pg',
            compatible: false,
            enabled: false,
            error: 'Available?: false, Loaded? false, Compatible? false, Patchable? false',
          )
        )
      end
    end
  end
end
