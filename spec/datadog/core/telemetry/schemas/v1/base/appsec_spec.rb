require 'spec_helper'

require 'datadog/core/telemetry/schemas/v1/base/appsec'
require 'datadog/core/telemetry/schemas/shared_examples'

RSpec.describe Datadog::Core::Telemetry::Schemas::V1::Base::AppSec do
  subject(:appsec) { described_class.new(version: version) }

  let(:version) { '1.0' }

  it { is_expected.to have_attributes(version: version) }

  describe '#initialize' do
    context ':version' do
      it_behaves_like 'a required string parameter', 'version'
    end
  end
end
