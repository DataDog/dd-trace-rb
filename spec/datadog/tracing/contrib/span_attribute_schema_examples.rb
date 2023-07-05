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
        expect(span.service).to eq('rspec')
      end
    end

    context 'v1 service name test with integration service name' do
      let(:configuration_options) { { service_name: 'configured' } }
      it do
        expect(span.service).to eq(configuration_options[:service_name])
      end
    end

    context 'test peer.service values' do
      it do
        skip('No let(:peer_service_val) defined.') unless defined?(peer_service_val)
        skip('No let(:peer_service_source) defined.') unless defined?(peer_service_source)

        expect(span.get_tag('peer.service')).to eq(peer_service_val)
        expect(span.get_tag('_dd.peer.service.source')).to eq(peer_service_source)
      end
    end
  end
end
