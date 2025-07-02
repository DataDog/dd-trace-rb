require 'spec_helper'

require 'datadog/core/telemetry/event/app_dependencies_loaded'

RSpec.describe Datadog::Core::Telemetry::Event::AppDependenciesLoaded do
  let(:id) { double('seq_id') }
  let(:event) { described_class.new }

  it_behaves_like 'telemetry event with no attributes'

  describe '.payload' do
    subject(:payload) { event.payload }

    it 'all have name and Ruby gem version' do
      is_expected.to match(dependencies: all(match(name: kind_of(String), version: kind_of(String))))
    end

    it 'has a known gem with expected version' do
      is_expected.to match(
        dependencies: include(name: 'datadog', version: Datadog::Core::Environment::Identity.gem_datadog_version)
      )
    end
  end
end
