require 'spec_helper'

require 'datadog/core/telemetry/schemas/v1/base/appsec'

RSpec.describe Datadog::Core::Telemetry::Schemas::V1::Base::AppSec do
  describe '#initialize' do
    let(:version) { '1.0' }

    subject(:appsec) { described_class.new(version) }
    it { is_expected.to be_a_kind_of(described_class) }

    it {
      is_expected.to have_attributes(version: version)
    }
  end
end
