RSpec.shared_examples 'schema version span' do
  before do
    subject
  end

  context 'service name env var testing' do
    around do |example|
      ClimateControl.modify(DD_TRACE_REMOVE_INTEGRATION_SERVICE_NAMES_ENABLED: 'true', DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1') do
        example.run
      end
    end

    context 'test the default' do
      around do |example|
        ClimateControl.modify(DD_SERVICE: 'rspec') do
          example.run
        end
      end

      it do
        expect(span.service).to eq('rspec')
        # service_name_map[span.trace_id] = 'rspec'
        # span.set_tag('_expected_service_name', 'rspec')
        # span.set_tag('_remove_integration_service_names_enabled', 'true')
      end
    end

    context 'service name test with integration service name' do
      around do |example|
        ClimateControl.modify(DD_SERVICE: 'configured') do
          example.run
        end
      end

      let(:configuration_options) { { service_name: 'configured' } }
      it do
        expect(span.service).to eq(configuration_options[:service_name])

        # # set the expected service name for the given trace_id
        # service_name_map[span.trace_id] = 'configured'
        # # span.set_tag('_expected_service_name', )
        # # span.set_tag('_remove_integration_service_names_enabled', 'true')
      end
    end
  end
end
