# typed: false

require 'spec_helper'

require 'datadog/profiling/transport/io/response'

RSpec.describe Datadog::Profiling::Transport::IO::Response do
  subject(:response) { described_class.new(result) }

  let(:result) { double('result') }

  it { is_expected.to be_a_kind_of(Datadog::Transport::IO::Response) }
  it { is_expected.to be_a_kind_of(Datadog::Profiling::Transport::Response) }
end
