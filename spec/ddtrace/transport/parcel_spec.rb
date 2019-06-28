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
  end
end
