RSpec.shared_examples 'a peer service span' do
  before { subject }

  let(:peer_service) { span.service }

  it 'contains peer service tag' do
    expect(span.get_tag('peer.service')).to_not be nil
    expect(span.get_tag('peer.service')).to eq(peer_service)
  end

  it 'contains peer hostname tag' do
    skip('No let(:peer_hostname) defined.') unless defined?(peer_hostname)

    expect(span.get_tag('peer.hostname')).to eq(peer_hostname)
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
