# frozen_string_literal: true

require 'spec_helper'
require 'active_support/lazy_load_hooks'

# Provide a minimal stub base class for testing without loading the full Rails framework.
# utils_spec.rb uses the same pattern (stub_const '::Rails') for the same reason.
module Rails
  class Railtie; end unless defined?(Railtie)
end

require 'lib/datadog/core/contrib/rails/railtie'

RSpec.describe Datadog::Core::Contrib::Rails::Railtie do
  describe '.after_initialize' do
    subject(:after_initialize) { described_class.after_initialize }

    before do
      allow(Datadog::Core::Contrib::Rails::Utils).to receive(:app_name).and_return('test_app')
    end

    after do
      Datadog::Core::Environment::Process.rails_application_name = nil
    end

    context 'when experimental_propagate_process_tags_enabled is true' do
      before do
        allow(Datadog.configuration).to receive(:experimental_propagate_process_tags_enabled).and_return(true)
        allow(Datadog::Core::ProcessDiscovery).to receive(:publish)
      end

      it 'includes the rails application name in process tags' do
        after_initialize
        expect(Datadog::Core::Environment::Process.tags).to include('rails.application:test_app')
      end

      it 're-publishes to process discovery' do
        after_initialize
        expect(Datadog::Core::ProcessDiscovery).to have_received(:publish).with(Datadog.configuration)
      end
    end

    context 'when experimental_propagate_process_tags_enabled is false' do
      before do
        allow(Datadog.configuration).to receive(:experimental_propagate_process_tags_enabled).and_return(false)
        allow(Datadog::Core::ProcessDiscovery).to receive(:publish)
      end

      it 'does not include the rails application name in process tags' do
        after_initialize
        expect(Datadog::Core::Environment::Process.tags).not_to include(a_string_starting_with('rails.application:'))
      end

      it 'does not publish to process discovery' do
        after_initialize
        expect(Datadog::Core::ProcessDiscovery).not_to have_received(:publish)
      end
    end
  end
end
