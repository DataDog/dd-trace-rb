require 'spec_helper'

require 'datadog/core/transport/request'

RSpec.describe Datadog::Core::Transport::Request do
  subject(:request) { described_class.new(parcel) }

  let(:parcel) { instance_double(Datadog::Core::Transport::Parcel) }

  describe '#initialize' do
    it { is_expected.to have_attributes(parcel: parcel) }

    context 'with no argument' do
      subject(:request) { described_class.new }

      it { is_expected.to have_attributes(parcel: nil) }
    end
  end
end
