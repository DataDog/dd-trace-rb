require 'spec_helper'

require 'ddtrace/transport/traces'

RSpec.describe Datadog::Transport::Traces::Parcel do
  subject(:parcel) { described_class.new(data, trace_count) }
  let(:data) { instance_double(Array) }
  let(:trace_count) { 123 }

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

  describe '#trace_count' do
    subject { parcel.trace_count }
    it { is_expected.to eq(trace_count) }
  end
end

RSpec.describe Datadog::Transport::Traces::Request do
  subject(:request) { described_class.new(data, trace_count) }
  let(:data) { double }
  let(:trace_count) { 1 }

  it { is_expected.to be_a_kind_of(Datadog::Transport::Request) }

  describe '#initialize' do
    it do
      is_expected.to have_attributes(parcel: kind_of(Datadog::Transport::Traces::Parcel))
    end
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
