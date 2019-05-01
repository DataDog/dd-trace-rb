require 'spec_helper'

require 'ddtrace'
require 'ddtrace/sync_writer'

RSpec.describe Datadog::SyncWriter do
  subject(:sync_writer) { described_class.new }

  describe '#runtime_metrics' do
    subject(:runtime_metrics) { sync_writer.runtime_metrics }
    it { is_expected.to be_a_kind_of(Datadog::Runtime::Metrics) }
  end
end
