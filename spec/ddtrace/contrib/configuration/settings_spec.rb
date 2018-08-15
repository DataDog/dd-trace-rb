require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Contrib::Configuration::Settings do
  subject(:settings) { described_class.new }

  it { is_expected.to be_a_kind_of(Datadog::Contrib::Configuration::Options) }

  describe '#options' do
    subject(:options) { settings.options }
    it { is_expected.to include(:service_name) }
    it { is_expected.to include(:tracer) }
  end
end
