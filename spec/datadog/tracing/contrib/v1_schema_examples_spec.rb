RSpec.shared_examples 'v1 schema test' do

  around do |example|
    ClimateControl.modify DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1' do
      example.run
    end
  end

  before do
    subject
  end

  context 'v1 service name test' do
    it 'test the v1 default' do
      expect(span.service).to eq('rspec')
    end
  end

  context 'v1 service name test with integration service name' do
    let(:configuration_options) { { service_name: 'configured' } }
    it { expect(span.service).to eq(configuration_options[:service_name]) }
  end
end

