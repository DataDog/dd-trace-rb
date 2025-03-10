RSpec.shared_examples 'a peer service span' do
  before do
    subject
    skip('No let(:peer_service_val) defined.') unless defined?(peer_service_val)
    skip('No let(:peer_service_source) defined.') unless defined?(peer_service_source)
  end

  context 'with default peer services enabled' do
    around do |example|
      ClimateControl.modify('DD_TRACE_PEER_SERVICE_DEFAULTS_ENABLED' => 'true') do
        example.run
      end
    end

    it 'contains extracted peer service tag' do
      expect(span.get_tag('peer.service')).to eq(peer_service_val)
      expect(span.get_tag('_dd.peer.service.source')).to eq(peer_service_source)
    end
  end

  context 'with default peer services disabled' do
    it 'does not contain extracted peer service tag' do
      expect(span.get_tag('peer.service')).to be_nil
      expect(span.get_tag('_dd.peer.service.source')).to be_nil
    end
  end
end

RSpec.shared_examples 'a non-peer service span' do
  before { subject }

  let(:peer_service) { span.service }

  it 'does not contain the peer service tag' do
    expect(span.get_tag('peer.service')).to be nil
  end

  it 'does not contain the peer hostname tag' do
    expect(span.get_tag('peer.hostname')).to be nil
  end
end
