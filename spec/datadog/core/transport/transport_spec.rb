require 'spec_helper'

require 'datadog/core/transport/transport'

# Some of the tests from spec/datadog/tracing/transport/traces_spec.rb
# could be ported to this file, if they are adjusted to not reference the
# Tracing::Traces transport but instead use a mock transport.

RSpec.describe Datadog::Core::Transport::Transport do
  let(:logger) { logger_allowing_debug }

  subject(:transport) { described_class.new(apis, current_api_id, logger: logger) }

  shared_context 'APIs with fallbacks' do
    let(:current_api_id) { :v2 }
    let(:apis) do
      Datadog::Core::Transport::HTTP::API::Map[
        v2: api_v2,
        v1: api_v1
      ].with_fallbacks(v2: :v1)
    end

    let(:api_v1) { instance_double(Datadog::Core::Transport::HTTP::API::Instance, 'v1', encoder: encoder_v1) }
    let(:api_v2) { instance_double(Datadog::Core::Transport::HTTP::API::Instance, 'v2', encoder: encoder_v2) }
    let(:encoder_v1) { instance_double(Datadog::Core::Encoding::Encoder, 'v1', content_type: 'text/plain') }
    let(:encoder_v2) { instance_double(Datadog::Core::Encoding::Encoder, 'v2', content_type: 'text/csv') }
  end

  describe '#initialize' do
    include_context 'APIs with fallbacks'

    it { is_expected.to have_attributes(apis: apis, current_api_id: current_api_id) }
  end

  describe '#downgrade?' do
    include_context 'APIs with fallbacks'

    subject(:downgrade?) { transport.send(:downgrade?, response) }

    let(:response) { instance_double(Datadog::Core::Transport::Response) }

    context 'when there is no fallback' do
      let(:current_api_id) { :v1 }

      it { is_expected.to be false }
    end

    context 'when a fallback is available' do
      let(:current_api_id) { :v2 }

      context 'and the response isn\'t \'not found\' or \'unsupported\'' do
        before do
          allow(response).to receive(:not_found?).and_return(false)
          allow(response).to receive(:unsupported?).and_return(false)
        end

        it { is_expected.to be false }
      end

      context 'and the response is \'not found\'' do
        before do
          allow(response).to receive(:not_found?).and_return(true)
          allow(response).to receive(:unsupported?).and_return(false)
        end

        it { is_expected.to be true }
      end

      context 'and the response is \'unsupported\'' do
        before do
          allow(response).to receive(:not_found?).and_return(false)
          allow(response).to receive(:unsupported?).and_return(true)
        end

        it { is_expected.to be true }
      end
    end
  end

  describe '#current_api' do
    include_context 'APIs with fallbacks'

    subject(:current_api) { transport.current_api }

    it { is_expected.to be(api_v2) }
  end

  describe '#set_api!' do
    include_context 'APIs with fallbacks'

    subject(:set_api!) { transport.send(:set_api!, api_id) }

    context 'when the API ID does not match an API' do
      let(:api_id) { :v99 }

      it { expect { set_api! }.to raise_error(Datadog::Core::Transport::UnknownApiVersionError) }
    end

    context 'when the API ID matches an API' do
      let(:api_id) { :v1 }

      it { expect { set_api! }.to change { transport.current_api }.from(api_v2).to(api_v1) }
    end
  end

  describe '#downgrade!' do
    include_context 'APIs with fallbacks'

    subject(:downgrade!) { transport.send(:downgrade!) }

    context 'when the API has no fallback' do
      let(:current_api_id) { :v1 }

      it { expect { downgrade! }.to raise_error(Datadog::Core::Transport::NoDowngradeAvailableError) }
    end

    context 'when the API has fallback' do
      let(:current_api_id) { :v2 }

      it { expect { downgrade! }.to change { transport.current_api }.from(api_v2).to(api_v1) }
    end
  end
end
