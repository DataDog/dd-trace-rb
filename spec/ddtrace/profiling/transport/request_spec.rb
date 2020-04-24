require 'spec_helper'

require 'ddtrace/profiling/transport/request'

RSpec.describe Datadog::Profiling::Transport::Request do
  subject(:request) { described_class.new(events) }
  let(:events) { instance_double(Array) }

  it { is_expected.to be_a_kind_of(Datadog::Transport::Request) }

  describe '#initialize' do
    it { is_expected.to have_attributes(parcel: kind_of(Datadog::Profiling::Transport::Parcel)) }
  end
end
