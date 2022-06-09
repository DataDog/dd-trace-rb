require 'spec_helper'

require 'datadog/core/telemetry/schemas/v1/base/product'
require 'datadog/core/telemetry/schemas/v1/base/appsec'
require 'datadog/core/telemetry/schemas/v1/base/profiler'

RSpec.describe Datadog::Core::Telemetry::Schemas::V1::Base::Product do
  subject(:product) { described_class.new(appsec: appsec, profiler: profiler) }

  let(:appsec) { Datadog::Core::Telemetry::Schemas::V1::Base::AppSec.new(version: '1.0') }
  let(:profiler) { Datadog::Core::Telemetry::Schemas::V1::Base::Profiler.new(version: '1.0') }

  it { is_expected.to have_attributes(appsec: appsec, profiler: profiler) }

  describe '#initialize' do
    context 'when :appsec' do
      context 'is nil' do
        let(:appsec) { nil }
        it { is_expected.to have_attributes(appsec: nil, profiler: profiler) }
        it { is_expected.to be_a_kind_of(described_class) }
      end

      context 'is not of type AppSec' do
        let(:appsec) { { version: '1.0' } }
        it { expect { product }.to raise_error(ArgumentError) }
      end

      context 'is valid' do
        let(:appsec) { Datadog::Core::Telemetry::Schemas::V1::Base::AppSec.new(version: '1.0') }
        it { is_expected.to be_a_kind_of(described_class) }
      end
    end

    context 'when :profiler' do
      context 'is nil' do
        let(:profiler) { nil }
        it { is_expected.to have_attributes(appsec: appsec, profiler: nil) }
        it { is_expected.to be_a_kind_of(described_class) }
      end

      context 'is not of type Profiler' do
        let(:profiler) { { version: '1.0' } }
        it { expect { product }.to raise_error(ArgumentError) }
      end

      context 'is valid' do
        let(:profiler) { Datadog::Core::Telemetry::Schemas::V1::Base::Profiler.new(version: '1.0') }
        it { is_expected.to be_a_kind_of(described_class) }
      end
    end

    context 'when :appsec and :profiler' do
      context 'are nil' do
        let(:appsec) { nil }
        let(:profiler) { nil }
        it { expect { product }.to raise_error(ArgumentError) }
      end
    end
  end
end
