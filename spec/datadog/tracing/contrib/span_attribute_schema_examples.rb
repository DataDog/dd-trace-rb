RSpec.shared_examples 'schema version span' do
  before do
    subject
  end

  context 'service name env var testing' do
    # setting DD_TRACE_SPAN_ATTRIBUTE_SCHEMA as the APM Test Agent relies on this ENV to run service naming assertions
    around do |example|
      ClimateControl.modify(
        DD_TRACE_REMOVE_INTEGRATION_SERVICE_NAMES_ENABLED: 'true',
        DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1'
      ) do
        example.run
      end
    end

    context 'test the default' do
      # setting DD_SERVICE for APM Test Agent service naming assertions
      around do |example|
        ClimateControl.modify(DD_TEST_EXPECTED_SERVICE: 'rspec') do
          example.run
        end
      end

      it do
        expect(span.service).to eq('rspec')
      end
    end

    context 'service name test with integration service name' do
      # setting DD_SERVICE for APM Test Agent service naming assertions
      around do |example|
        ClimateControl.modify(DD_TEST_EXPECTED_SERVICE: 'configured') do
          example.run
        end
      end

      let(:configuration_options) { { service_name: 'configured' } }
      it do
        expect(span.service).to eq(configuration_options[:service_name])
        expect(span.get_tag('_dd.base_service')).to eq('rspec')
      end
    end
  end
end
