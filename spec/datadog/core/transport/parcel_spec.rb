require 'spec_helper'

require 'datadog/core/transport/parcel'

RSpec.describe Datadog::Core::Transport::Parcel do
  subject(:parcel) { described_class.new(data) }

  let(:data) { double('data') }

  describe '#initialize' do
    it { is_expected.to have_attributes(data: data) }
  end

  describe '#length' do
    subject(:length) { parcel.length }

    let(:length) { double('length') }

    before { expect(data).to receive(:length).and_return(length) }

    it { is_expected.to be length }
  end

  describe '#encode_with' do
    subject(:encode_with) { parcel.encode_with(encoder) }

    let(:encoder) { double('encoder') }

    it { expect { encode_with }.to raise_error(NotImplementedError) }
  end
end
