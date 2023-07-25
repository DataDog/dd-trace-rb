RSpec.shared_examples 'schema version span' do
  before do
    subject
  end

  context 'v1 testing' do
    around do |example|
      ClimateControl.modify DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1' do
        example.run
      end
    end

    context 'test the v1 default' do
      it do
        skip('v1 is not fully implemented')
        expect(span.service).to eq('rspec')
      end
    end

    context 'v1 service name test with integration service name' do
      let(:configuration_options) { { service_name: 'configured' } }
      it do
        skip('v1 is not fully implemented')
        expect(span.service).to eq(configuration_options[:service_name])
      end
    end
  end

  context 'service name env var testing' do
    around do |example|
      ClimateControl.modify DD_TRACE_REMOVE_INTEGRATION_SERVICE_NAMES_ENABLED: 'true' do
        example.run
      end
    end

    context 'test the default' do
      it do
        expect(span.service).to eq('rspec')
      end
    end

    context 'service name test with integration service name' do
      let(:configuration_options) { { service_name: 'configured' } }
      it do
        expect(span.service).to eq(configuration_options[:service_name])
      end
    end
  end
end
