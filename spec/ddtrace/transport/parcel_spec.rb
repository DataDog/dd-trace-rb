require 'spec_helper'

require 'ddtrace/transport/parcel'

RSpec.describe Datadog::Transport::Parcel do
  context 'when implemented by a class' do
    subject(:parcel) { parcel_class.new(data) }
    let(:parcel_class) do
      stub_const('TestParcel', Class.new { include Datadog::Transport::Parcel })
    end
    let(:data) { double('data') }

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
end
