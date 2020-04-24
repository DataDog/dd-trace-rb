require 'spec_helper'

require 'ddtrace/profiling/transport/parcel'

RSpec.describe Datadog::Profiling::Transport::Parcel do
  subject(:parcel) { described_class.new(data) }
  let(:data) { instance_double(Array) }

  it { is_expected.to be_a_kind_of(Datadog::Transport::Parcel) }

  describe '#initialize' do
    it { is_expected.to have_attributes(data: data) }
  end

  describe '#encode_with' do
    subject(:encode_with) { parcel.encode_with(encoder) }
    let(:encoder) { instance_double(Datadog::Encoding::Encoder) }
    let(:encoded_data) { double('encoded data') }

    before do
      expect(encoder).to receive(:encode)
        .with(data)
        .and_return(encoded_data)
    end

    it { is_expected.to be encoded_data }
  end
end
