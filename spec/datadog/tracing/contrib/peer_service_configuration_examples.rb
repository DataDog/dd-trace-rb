RSpec.shared_examples_for 'configured peer service span' do |env_service_name_key, error: nil|
  context "when given `#{env_service_name_key}` environment variable" do
    around do |example|
      ClimateControl.modify(env_service_name_key => 'configured_peer_service') do
        example.run
      end
    end

    before do
      if error
        expect { subject }.to raise_error error
      else
        subject
      end
    end

    context 'when peer.service is configured' do
      it 'expects peer.service to equal configured value and source to be peer.service' do
        expect(span.get_tag('peer.service')).to eq('configured_peer_service')
        expect(span.get_tag('_dd.peer.service.source')).to eq('peer.service')
      end
    end
  end
end
