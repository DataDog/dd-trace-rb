require 'spec_helper'

require 'datadog/core/transport/http'

RSpec.describe Datadog::Core::Transport::HTTP do
  describe '.default_headers' do
    subject(:default_headers) { described_class.default_headers }

    it do
      is_expected.to include(
        Datadog::Core::Transport::Ext::HTTP::HEADER_CLIENT_COMPUTED_TOP_LEVEL => '1',
        Datadog::Core::Transport::Ext::HTTP::HEADER_META_LANG => Datadog::Core::Environment::Ext::LANG,
        Datadog::Core::Transport::Ext::HTTP::HEADER_META_LANG_VERSION => Datadog::Core::Environment::Ext::LANG_VERSION,
        Datadog::Core::Transport::Ext::HTTP::HEADER_META_LANG_INTERPRETER =>
          Datadog::Core::Environment::Ext::LANG_INTERPRETER,
        'Datadog-Meta-Lang-Interpreter-Vendor' => RUBY_ENGINE,
        Datadog::Core::Transport::Ext::HTTP::HEADER_META_TRACER_VERSION =>
          Datadog::Core::Environment::Ext::GEM_DATADOG_VERSION
      )
    end

    context 'when Core::Environment::Container.container_id' do
      before { expect(Datadog::Core::Environment::Container).to receive(:container_id).and_return(container_id) }

      context 'is not nil' do
        let(:container_id) { '3726184226f5d3147c25fdeab5b60097e378e8a720503a5e19ecfdf29f869860' }

        it { is_expected.to include(Datadog::Core::Transport::Ext::HTTP::HEADER_CONTAINER_ID => container_id) }
      end

      context 'is nil' do
        let(:container_id) { nil }

        it { is_expected.to_not include(Datadog::Core::Transport::Ext::HTTP::HEADER_CONTAINER_ID) }
      end
    end

    context 'when Datadog.configuration.apm.tracing.enabled' do
      before { expect(Datadog.configuration.apm.tracing).to receive(:enabled).and_return(apm_tracing_enabled) }

      context 'is false' do
        let(:apm_tracing_enabled) { false }

        it { is_expected.to include(Datadog::Core::Transport::Ext::HTTP::HEADER_CLIENT_COMPUTED_STATS => 'yes') }
      end

      context 'is true' do
        let(:apm_tracing_enabled) { true }

        it { is_expected.to_not include(Datadog::Core::Transport::Ext::HTTP::HEADER_CLIENT_COMPUTED_STATS) }
      end
    end
  end
end
