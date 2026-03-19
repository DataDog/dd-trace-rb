# frozen_string_literal: true

require 'datadog/core'
require 'datadog/core/transport/http'

RSpec.describe 'Client-side stats header signaling' do
  describe 'Datadog::Core::Transport::HTTP.default_headers' do
    context 'when stats_computation is enabled' do
      before do
        allow(Datadog.configuration.tracing.stats_computation).to receive(:enabled).and_return(true)
        allow(Datadog.configuration.apm.tracing).to receive(:enabled).and_return(true)
      end

      it 'includes the Datadog-Client-Computed-Stats header' do
        headers = Datadog::Core::Transport::HTTP.default_headers
        expect(headers).to include(
          Datadog::Core::Transport::Ext::HTTP::HEADER_CLIENT_COMPUTED_STATS => 'yes'
        )
      end

      it 'includes the Datadog-Client-Computed-Top-Level header' do
        headers = Datadog::Core::Transport::HTTP.default_headers
        expect(headers).to include(
          Datadog::Core::Transport::Ext::HTTP::HEADER_CLIENT_COMPUTED_TOP_LEVEL => '1'
        )
      end
    end

    context 'when stats_computation is disabled and tracing is enabled' do
      before do
        allow(Datadog.configuration.tracing.stats_computation).to receive(:enabled).and_return(false)
        allow(Datadog.configuration.apm.tracing).to receive(:enabled).and_return(true)
      end

      it 'does not include the Datadog-Client-Computed-Stats header' do
        headers = Datadog::Core::Transport::HTTP.default_headers
        expect(headers).not_to have_key(
          Datadog::Core::Transport::Ext::HTTP::HEADER_CLIENT_COMPUTED_STATS
        )
      end
    end

    context 'when apm tracing is disabled' do
      before do
        allow(Datadog.configuration.apm.tracing).to receive(:enabled).and_return(false)
      end

      it 'includes the Datadog-Client-Computed-Stats header' do
        headers = Datadog::Core::Transport::HTTP.default_headers
        expect(headers).to include(
          Datadog::Core::Transport::Ext::HTTP::HEADER_CLIENT_COMPUTED_STATS => 'yes'
        )
      end
    end
  end
end
