require 'spec_helper'

require 'datadog/core/telemetry/schemas/v1/base/product'
require 'datadog/core/telemetry/schemas/v1/base/appsec'
require 'datadog/core/telemetry/schemas/v1/base/profiler'

RSpec.describe Datadog::Core::Telemetry::Schemas::V1::Base::Product do
  describe '#initialize' do
    context 'given no parameters' do
      subject(:products) { described_class.new }
      it { is_expected.to be_a_kind_of(described_class) }
    end

    context 'given all parameters' do
      subject(:host) { described_class.new(appsec: appsec, profiler: profiler) }
      let(:appsec) { { appsec: { version: '1.0' } } }
      let(:profiler) { { profiler: { version: '1.0' } } }
      it {
        is_expected.to have_attributes(appsec: appsec, profiler: profiler)
      }
    end
  end
end
