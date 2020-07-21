require 'spec_helper'

require 'ddtrace/profiling/flush'
require 'ddtrace/profiling/transport/request'

RSpec.describe Datadog::Profiling::Transport::Request do
  subject(:request) { described_class.new(flush) }
  let(:flush) { instance_double(Datadog::Profiling::Flush) }

  it { is_expected.to be_a_kind_of(Datadog::Transport::Request) }

  describe '#initialize' do
    it { is_expected.to have_attributes(parcel: kind_of(Datadog::Profiling::Transport::Parcel)) }
    it { expect(request.parcel.data).to be(flush) }
  end
end
