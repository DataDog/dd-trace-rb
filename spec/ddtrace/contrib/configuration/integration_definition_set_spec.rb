require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Contrib::Configuration::IntegrationDefinitionSet do
  subject(:set) { described_class.new }

  it { is_expected.to be_a_kind_of(Hash) }
end
