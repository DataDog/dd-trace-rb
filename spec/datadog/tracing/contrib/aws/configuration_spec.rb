require 'datadog/tracing/contrib/aws/configuration/settings'

RSpec.describe Datadog::Tracing::Contrib::Aws::Configuration::Settings do
  describe 'Option `service_name`' do
    context 'when with service_name' do # default to include base
      it do
        expect(described_class.new(service_name: 'test-service').service_name).to eq('test-service')
      end
    end

    context 'when without service_name v0' do # default to include base
      it do
        with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v0' do
          expect(described_class.new.service_name).to eq('aws')
        end
      end
    end

    context 'when without service_name v1' do # default to include base
      it do
        with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1' do
          expect(described_class.new.service_name).to eq('rspec')
        end
      end
    end
  end

  def with_modified_env(options = {}, &block)
    ClimateControl.modify(options, &block)
  end
end
