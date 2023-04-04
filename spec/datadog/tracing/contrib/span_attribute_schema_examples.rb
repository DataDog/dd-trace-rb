RSpec.shared_examples 'span attributes schema' do
  before do
    subject
  end

  context 'v0 testing' do
    it 'has schema attribute span tag as v0' do
      expect(span.get_tag('_dd.trace_span_attribute_schema')).to eq('v0')
    end
  end

  context 'v1 testing' do
    around do |example|
      ClimateControl.modify DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1' do
        example.run
      end
    end

    context 'test the v1 default' do
      it do
        expect(span.service).to eq('rspec')
        expect(span.get_tag('_dd.trace_span_attribute_schema')).to eq('v1')
      end
    end

    context 'v1 service name test with integration service name' do
      let(:configuration_options) { { service_name: 'configured' } }
      it do
        expect(span.service).to eq(configuration_options[:service_name])
        expect(span.get_tag('_dd.trace_span_attribute_schema')).to eq('v1')
      end
    end
  end
end
