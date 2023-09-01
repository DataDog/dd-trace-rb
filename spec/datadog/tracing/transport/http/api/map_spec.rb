require 'spec_helper'

require 'datadog/tracing/transport/http/api/map'

RSpec.describe Datadog::Tracing::Transport::HTTP::API::Map do
  subject(:map) { described_class.new }

  it { is_expected.to be_a_kind_of(Hash) }
  it { is_expected.to be_a_kind_of(Datadog::Tracing::Transport::HTTP::API::Fallbacks) }
end
