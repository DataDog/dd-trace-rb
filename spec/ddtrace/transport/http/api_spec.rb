require 'spec_helper'

require 'ddtrace/transport/http/api'

RSpec.describe Datadog::Transport::HTTP::API do
  describe '.defaults' do
    subject(:defaults) { described_class.defaults }

    it { is_expected.to be_a_kind_of(Datadog::Transport::HTTP::API::Map) }

    it do
      is_expected.to include(
        described_class::V4 => kind_of(Datadog::Transport::HTTP::API::Spec),
        described_class::V3 => kind_of(Datadog::Transport::HTTP::API::Spec),
      )

      defaults[described_class::V4].tap do |v4|
        expect(v4).to be_a_kind_of(Datadog::Transport::HTTP::Traces::API::Spec)
        expect(v4.traces).to be_a_kind_of(Datadog::Transport::HTTP::Traces::API::Endpoint)
        expect(v4.traces.service_rates?).to be true
        expect(v4.traces.encoder).to be Datadog::Core::Encoding::MsgpackEncoder
      end

      defaults[described_class::V3].tap do |v3|
        expect(v3).to be_a_kind_of(Datadog::Transport::HTTP::Traces::API::Spec)
        expect(v3.traces).to be_a_kind_of(Datadog::Transport::HTTP::Traces::API::Endpoint)
        expect(v3.traces.service_rates?).to be false
        expect(v3.traces.encoder).to be Datadog::Core::Encoding::MsgpackEncoder
      end
    end

    describe '#fallbacks' do
      subject(:fallbacks) { defaults.fallbacks }

      it do
        is_expected.to include(described_class::V4 => described_class::V3)
      end
    end
  end
end
