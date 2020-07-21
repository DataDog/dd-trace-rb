require 'spec_helper'

require 'ddtrace/profiling/transport/http/api'

RSpec.describe Datadog::Profiling::Transport::HTTP::API do
  describe '::agent_defaults' do
    subject(:agent_defaults) { described_class.agent_defaults }
    it { is_expected.to be_a_kind_of(Datadog::Transport::HTTP::API::Map) }

    it do
      is_expected.to include(
        described_class::V1 => kind_of(Datadog::Profiling::Transport::HTTP::API::Spec)
      )

      agent_defaults[described_class::V1].tap do |v1|
        expect(v1).to be_a_kind_of(Datadog::Profiling::Transport::HTTP::API::Spec)
        expect(v1.profiles).to be_a_kind_of(Datadog::Profiling::Transport::HTTP::API::Endpoint)
        expect(v1.profiles.path).to eq('/profiling/v1/input')
        expect(v1.profiles.encoder).to be Datadog::Profiling::Encoding::Profile::Protobuf
      end
    end
  end

  describe '::api_defaults' do
    subject(:api_defaults) { described_class.api_defaults }
    it { is_expected.to be_a_kind_of(Datadog::Transport::HTTP::API::Map) }

    it do
      is_expected.to include(
        described_class::V1 => kind_of(Datadog::Profiling::Transport::HTTP::API::Spec)
      )

      api_defaults[described_class::V1].tap do |v1|
        expect(v1).to be_a_kind_of(Datadog::Profiling::Transport::HTTP::API::Spec)
        expect(v1.profiles).to be_a_kind_of(Datadog::Profiling::Transport::HTTP::API::Endpoint)
        expect(v1.profiles.path).to eq('/v1/input')
        expect(v1.profiles.encoder).to be Datadog::Profiling::Encoding::Profile::Protobuf
      end
    end
  end
end
