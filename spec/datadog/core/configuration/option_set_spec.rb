require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Core::Configuration::OptionSet do
  subject(:set) { described_class.new }

  it { is_expected.to be_a_kind_of(Hash) }
end
