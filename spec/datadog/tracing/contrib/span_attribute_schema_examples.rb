RSpec.shared_examples 'schema version span' do |peer_service_val|
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

        # TODO: change when new peer.service tag is added for v1
        expect(span.get_tag('peer.service')).to eq(peer_service_val)
      end
    end

    context 'v1 service name test with integration service name' do
      let(:configuration_options) { { service_name: 'configured' } }
      it do
        expect(span.service).to eq(configuration_options[:service_name])

        # TODO: change when new peer.service tag is added for v1
        expect(span.get_tag('peer.service')).to eq(peer_service_val)
      end
    end
  end
end
