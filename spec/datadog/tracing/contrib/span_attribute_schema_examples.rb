RSpec.shared_examples 'schema version span' do
  before do
    subject
    # _dd.base_service is set in SpanOperation#finish. If the integration
    # test uses an open SpanOperation as `span` (e.g. because the complete
    # callback is mocked out), finish it now so the tag is available.
    span.finish if span.respond_to?(:finished?) && !span.finished?
  end

  context 'service name env var testing' do
    # setting DD_TRACE_SPAN_ATTRIBUTE_SCHEMA as the APM Test Agent relies on this ENV to run service naming assertions
    with_env DD_TRACE_REMOVE_INTEGRATION_SERVICE_NAMES_ENABLED: 'true',
      DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1'

    context 'test the default' do
      # setting DD_SERVICE for APM Test Agent service naming assertions
      with_env DD_TEST_EXPECTED_SERVICE: 'rspec'

      it do
        expect(span.service).to eq('rspec')
      end
    end

    context 'service name test with integration service name' do
      # setting DD_SERVICE for APM Test Agent service naming assertions
      with_env DD_TEST_EXPECTED_SERVICE: 'configured'

      let(:configuration_options) { {service_name: 'configured'} }
      it do
        expect(span.service).to eq(configuration_options[:service_name])
        expect(span.get_tag('_dd.base_service')).to eq('rspec')
      end
    end
  end
end
