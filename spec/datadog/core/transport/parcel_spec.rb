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

    let(:expected_length) { double('length') }

    before { expect(data).to receive(:length).and_return(expected_length) }

    it { is_expected.to be expected_length }
  end
end
