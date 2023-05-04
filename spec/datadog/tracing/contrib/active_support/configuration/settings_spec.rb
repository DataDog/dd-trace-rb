require 'datadog/tracing/contrib/active_support/configuration/settings'
require 'datadog/tracing/contrib/service_name_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::ActiveSupport::Configuration::Settings do
  describe 'Option `cache_service`' do
    context 'when with cache_service' do # default to include base
      it do
        expect(described_class.new(cache_service: 'test-service').cache_service).to eq('test-service')
      end
    end

    context 'when without service_name v0' do # default to include base
      it do
        with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v0' do
          expect(described_class.new.cache_service).to eq('active_support-cache')
        end
      end
    end

    context 'when without service_name v1' do # default to include base
      it do
        with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1' do
          expect(described_class.new.cache_service).to eq('rspec')
        end
      end
    end
  end

  def with_modified_env(options = {}, &block)
    ClimateControl.modify(options, &block)
  end
end
