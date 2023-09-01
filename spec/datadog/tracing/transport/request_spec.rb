require 'spec_helper'

require 'datadog/tracing/transport/request'

RSpec.describe Datadog::Tracing::Transport::Request do
  subject(:request) { described_class.new(parcel) }

  let(:parcel) { instance_double(Datadog::Tracing::Transport::Parcel) }

  describe '#initialize' do
    it { is_expected.to have_attributes(parcel: parcel) }

    context 'with no argument' do
      subject(:request) { described_class.new }

      it { is_expected.to have_attributes(parcel: nil) }
    end
  end
end
