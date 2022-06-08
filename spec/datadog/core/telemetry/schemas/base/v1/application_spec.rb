require 'spec_helper'

require 'datadog/core/telemetry/schemas/v1/base/application'

RSpec.describe Datadog::Core::Telemetry::Schemas::V1::Base::Application do
  describe '#initialize' do
    let(:env) { 'prod' }
    let(:language_name) { 'ruby' }
    let(:language_version) { '3.0' }
    let(:products) { { appsec: { version: '1.0' } } }
    let(:runtime_name) { 'ruby30' }
    let(:runtime_patches) { 'patch' }
    let(:runtime_version) { '3.2.1' }
    let(:service_name) { 'myapp' }
    let(:service_version) { '1.2.3' }
    let(:tracer_version) { '1.0' }

    context 'given only required parameters' do
      subject(:application) do
        described_class.new(
          language_version: language_version,
          service_name: service_name,
          language_name: language_name,
          tracer_version: tracer_version
        )
      end
      it { is_expected.to be_a_kind_of(described_class) }

      it do
        is_expected.to have_attributes(
          language_name: language_name,
          language_version: language_version,
          service_name: service_name,
          tracer_version: tracer_version
        )
      end

      it do
        is_expected.to have_attributes(
          env: nil,
          products: nil,
          runtime_name: nil,
          runtime_patches: nil,
          runtime_version: nil,
          service_version: nil,
        )
      end
    end

    context 'given all parameters' do
      subject(:application) do
        described_class.new(
          env: env,
          language_name: language_name,
          language_version: language_version,
          products: products,
          runtime_name: runtime_name,
          runtime_patches: runtime_patches,
          runtime_version: runtime_version,
          service_name: service_name,
          service_version: service_version,
          tracer_version: tracer_version
        )
      end
      it do
        is_expected.to have_attributes(
          env: env,
          language_name: language_name,
          language_version: language_version,
          products: products,
          runtime_name: runtime_name,
          runtime_patches: runtime_patches,
          runtime_version: runtime_version,
          service_name: service_name,
          service_version: service_version,
          tracer_version: tracer_version
        )
      end
    end
  end
end
