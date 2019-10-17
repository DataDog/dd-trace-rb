require 'spec_helper'

require 'ddtrace/transport/request'

RSpec.describe Datadog::Transport::Request do
  subject(:request) { described_class.new(parcel, trace_count, content_type) }
  let(:parcel) { instance_double(Datadog::Transport::Parcel) }
  let(:trace_count) { 1 }
  let(:content_type) { 'text/plain' }

  describe '#initialize' do
    it { is_expected.to have_attributes(parcel: parcel) }
  end
end
