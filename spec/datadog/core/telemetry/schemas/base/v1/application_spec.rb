require 'spec_helper'

require 'datadog/core/telemetry/schemas/v1/base/application'

RSpec.describe Datadog::Core::Telemetry::Schemas::V1::Base::Application do
  describe '#initialize' do
    let(:language_name) { 'ruby' }
    let(:language_version) { '3.0' }
    let(:service_name) { 'myapp' }
    let(:tracer_version) { '1.0' }
    let(:env) { 'prod' }
    let(:runtime_name) { 'ruby30' }
    let(:runtime_patches) { 'patch' }
    let(:runtime_version) { '3.2.1' }
    let(:service_version) { '1.2.3' }
    let(:products) { { appsec: { version: '1.0' } } }

    context 'given only required parameters' do
      subject(:application) do
        described_class.new(language_name: language_name, language_version: language_version, service_name: service_name,
                            tracer_version: tracer_version)
      end
      it { is_expected.to be_a_kind_of(described_class) }

      it {
        is_expected.to have_attributes(language_name: language_name, language_version: language_version,
                                       service_name: service_name, tracer_version: tracer_version)
      }

      it {
        is_expected.to have_attributes(env: nil, runtime_name: nil, runtime_patches: nil, runtime_version: nil,
                                       service_version: nil, products: nil)
      }
    end

    context 'given all parameters' do
      subject(:application) do
        described_class.new(language_name: language_name, language_version: language_version, service_name: service_name,
                            tracer_version: tracer_version, env: env, runtime_name: runtime_name,
                            runtime_patches: runtime_patches, runtime_version: runtime_version,
                            service_version: service_version, products: products)
      end
      it {
        is_expected
          .to have_attributes(language_name: language_name, language_version: language_version, service_name: service_name,
                              tracer_version: tracer_version, env: env, runtime_name: runtime_name,
                              runtime_patches: runtime_patches, runtime_version: runtime_version,
                              service_version: service_version, products: products)
      }
    end
  end
end
