require 'spec_helper'

require 'ddtrace/profiling/buffer'

RSpec.describe Datadog::Profiling::Buffer do
  subject(:buffer) { described_class.new(max_size) }
  let(:max_size) { 0 }

  it { is_expected.to be_a_kind_of(Datadog::Buffer) }
end
