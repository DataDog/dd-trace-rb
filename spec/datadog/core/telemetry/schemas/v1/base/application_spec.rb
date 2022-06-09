require 'spec_helper'

require 'datadog/core/telemetry/schemas/shared_examples'
require 'datadog/core/telemetry/schemas/v1/base/application'
require 'datadog/core/telemetry/schemas/v1/base/product'
require 'datadog/core/telemetry/schemas/v1/base/appsec'
require 'datadog/core/telemetry/schemas/v1/base/profiler'

RSpec.describe Datadog::Core::Telemetry::Schemas::V1::Base::Application do
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

  let(:env) { 'prod' }
  let(:language_name) { 'ruby' }
  let(:language_version) { '3.0' }
  let(:products) do
    Datadog::Core::Telemetry::Schemas::V1::Base::Product.new(
      appsec: Datadog::Core::Telemetry::Schemas::V1::Base::AppSec.new(version: '1.0'),
      profiler: Datadog::Core::Telemetry::Schemas::V1::Base::Profiler.new(version: '1.0')
    )
  end
  let(:runtime_name) { 'ruby30' }
  let(:runtime_patches) { 'patch' }
  let(:runtime_version) { '3.2.1' }
  let(:service_name) { 'myapp' }
  let(:service_version) { '1.2.3' }
  let(:tracer_version) { '1.0' }

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

  describe '#initialize' do
    context 'when :language_name' do
      it_behaves_like 'a string argument', 'language_name'
    end

    context 'when :language_version' do
      it_behaves_like 'a string argument', 'language_version'
    end

    context 'when :service_name' do
      it_behaves_like 'a string argument', 'service_name'
    end

    context 'when :tracer_version' do
      it_behaves_like 'a string argument', 'tracer_version'
    end

    context 'when :env' do
      it_behaves_like 'an optional string argument', 'env'
    end

    context 'when :runtime_name' do
      it_behaves_like 'an optional string argument', 'runtime_name'
    end

    context 'when :runtime_patches' do
      it_behaves_like 'an optional string argument', 'runtime_patches'
    end

    context 'when :runtime_version' do
      it_behaves_like 'an optional string argument', 'runtime_version'
    end

    context 'when :service_version' do
      it_behaves_like 'an optional string argument', 'service_version'
    end

    context 'when :products' do
      context 'is nil' do
        let(:products) { nil }
        it { is_expected.to be_a_kind_of(described_class) }
      end

      context 'is not of type products' do
        let(:products) { { version: '1.0' } }
        it { expect { application }.to raise_error(ArgumentError) }
      end

      context 'is valid' do
        let(:products) do
          Datadog::Core::Telemetry::Schemas::V1::Base::Product.new(
            appsec: Datadog::Core::Telemetry::Schemas::V1::Base::AppSec.new(version: '1.0'),
            profiler: Datadog::Core::Telemetry::Schemas::V1::Base::Profiler.new(version: '1.0')
          )
        end
        it { is_expected.to be_a_kind_of(described_class) }
      end
    end
  end
end
