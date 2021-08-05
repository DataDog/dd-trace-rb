# typed: ignore
RSpec.shared_examples 'a peer service span' do
  before { subject }

  let(:peer_service) { span.service }

  it 'contains peer service tag' do
    expect(span.get_tag('peer.service')).to_not be nil
    expect(span.get_tag('peer.service')).to eq(peer_service)
  end
end

RSpec.shared_examples 'a non-peer service span' do
  before { subject }

  let(:peer_service) { span.service }

  it 'does not contain a peer service tag' do
    expect(span.get_tag('peer.service')).to be nil
  end
end
