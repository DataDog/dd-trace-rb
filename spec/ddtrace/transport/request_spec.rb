require 'spec_helper'

require 'ddtrace/transport/request'

RSpec.describe Datadog::Transport::Request do
  subject(:request) { described_class.new(parcel) }

  let(:parcel) { instance_double(Datadog::Transport::Parcel) }

  describe '#initialize' do
    it { is_expected.to have_attributes(parcel: parcel) }
  end
end
