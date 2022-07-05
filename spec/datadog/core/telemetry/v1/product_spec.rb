require 'spec_helper'

require 'datadog/core/telemetry/v1/product'

RSpec.describe Datadog::Core::Telemetry::V1::Product do
  subject(:product) { described_class.new(appsec: appsec, profiler: profiler) }

  let(:appsec) { { version: '1.0' } }
  let(:profiler) { { version: '1.0' } }

  it { is_expected.to have_attributes(appsec: appsec, profiler: profiler) }

  describe '#initialize' do
    context 'when :appsec' do
      context 'is nil' do
        let(:appsec) { nil }
        it { is_expected.to have_attributes(appsec: nil, profiler: profiler) }
        it { is_expected.to be_a_kind_of(described_class) }
      end

      context 'is valid' do
        let(:appsec) { { version: '1.0' } }
        it { is_expected.to be_a_kind_of(described_class) }
      end
    end

    context 'when :profiler' do
      context 'is nil' do
        let(:profiler) { nil }
        it { is_expected.to have_attributes(appsec: appsec, profiler: nil) }
        it { is_expected.to be_a_kind_of(described_class) }
      end

      context 'is valid' do
        let(:profiler) { { version: '1.0' } }
        it { is_expected.to be_a_kind_of(described_class) }
      end
    end
  end

  describe '#to_h' do
    subject(:to_h) { product.to_h }

    let(:appsec) { { version: '1.0' } }
    let(:profiler) { { version: '1.0' } }

    it do
      is_expected.to eq(
        appsec: { version: '1.0' },
        profiler: { version: '1.0' }
      )
    end
  end
end
