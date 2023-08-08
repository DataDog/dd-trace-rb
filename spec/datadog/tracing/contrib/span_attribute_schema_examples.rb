RSpec.shared_examples 'schema version span' do
  before do
    subject
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
        span.set_tag("_expected_service_name", 'rspec')
        span.set_tag("_remove_integration_service_names_enabled", "true")
      end
    end

    context 'service name test with integration service name' do
      let(:configuration_options) { { service_name: 'configured-span-attr' } }
      it do
        expect(span.service).to eq(configuration_options[:service_name])
        span.set_tag("_expected_service_name", configuration_options[:service_name])
        span.set_tag("_remove_integration_service_names_enabled", "true")
      end
    end
  end
end
