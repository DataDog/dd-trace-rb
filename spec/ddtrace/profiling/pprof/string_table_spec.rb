require 'spec_helper'

require 'ddtrace/profiling/pprof/string_table'

RSpec.describe Datadog::Profiling::Pprof::StringTable do
  subject(:string_table) { described_class.new }
  it { is_expected.to be_a_kind_of(Datadog::Utils::StringTable) }
end
