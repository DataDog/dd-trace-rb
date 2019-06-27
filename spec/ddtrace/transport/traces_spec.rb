require 'spec_helper'

require 'ddtrace/transport/traces'

RSpec.describe Datadog::Transport::Traces::Parcel do
  subject(:parcel) { described_class.new(data) }
  let(:data) { instance_double(Array) }

  it { is_expected.to be_a_kind_of(Datadog::Transport::Parcel) }

  describe '#initialize' do
    it { is_expected.to have_attributes(data: data) }
  end

  describe '#count' do
    subject(:count) { parcel.count }
    let(:length) { double('length') }

    before { expect(data).to receive(:length).and_return(length) }

    it { is_expected.to be length }
  end

  describe '#encode_with' do
    subject(:encode_with) { parcel.encode_with(encoder) }
    let(:encoder) { instance_double(Datadog::Encoding::Encoder) }
    let(:encoded_data) { double('encoded data') }

    before do
      expect(encoder).to receive(:encode_traces)
        .with(data)
        .and_return(encoded_data)
    end

    it { is_expected.to be encoded_data }
  end
end

RSpec.describe Datadog::Transport::Traces::Request do
  subject(:request) { described_class.new(traces) }
  let(:traces) { instance_double(Array) }

  it { is_expected.to be_a_kind_of(Datadog::Transport::Request) }

  describe '#initialize' do
    it { is_expected.to have_attributes(parcel: kind_of(Datadog::Transport::Traces::Parcel)) }
  end
end

RSpec.describe Datadog::Transport::Traces::Response do
  context 'when implemented by a class' do
    subject(:response) { response_class.new }

    let(:response_class) do
      stub_const('TestResponse', Class.new { include Datadog::Transport::Traces::Response })
    end

    describe '#service_rates' do
      it { is_expected.to respond_to(:service_rates) }
    end
  end
end
