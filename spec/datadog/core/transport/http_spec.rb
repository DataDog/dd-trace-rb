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

    context 'when Container.to_headers returns headers' do
      let(:container_headers) do
        {
          'Datadog-Container-ID' => 'abc123',
          'Datadog-Entity-ID' => 'ci-abc123',
          'Datadog-External-Env' => 'provided-by-container-runner'
        }
      end

      before do
        allow(Datadog::Core::Environment::Container).to receive(:to_headers).and_return(container_headers)
      end

      it 'merges container headers into default headers' do
        expect(default_headers).to include(container_headers)
      end
    end

    context 'when Container.to_headers returns empty hash' do
      before do
        allow(Datadog::Core::Environment::Container).to receive(:to_headers).and_return({})
      end

      it 'does not include any container headers' do
        expect(default_headers).to_not include('Datadog-Container-ID')
        expect(default_headers).to_not include('Datadog-Entity-ID')
        expect(default_headers).to_not include('Datadog-External-Env')
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
