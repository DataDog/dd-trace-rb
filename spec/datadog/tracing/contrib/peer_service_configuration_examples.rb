RSpec.shared_examples_for 'configured peer service span' do |env_service_name_key, error: nil|
  context "when given `#{env_service_name_key}` environment variable" do
    around do |example|
      ClimateControl.modify(env_service_name_key => 'configured_peer_service_via_env_var') do
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

    context 'with default peer services enabled' do
      around do |example|
        ClimateControl.modify('DD_TRACE_PEER_SERVICE_DEFAULTS_ENABLED' => 'true') do
          example.run
        end
      end

      context 'when env_var configured' do
        it 'expects peer.service to equal env var value and source to be peer.service' do
          expect(span.get_tag('peer.service')).to eq('configured_peer_service_via_env_var')
          expect(span.get_tag('_dd.peer.service.source')).to eq('peer.service')
        end
      end

      context 'when peer_service option is configured' do
        let(:configuration_options) { { peer_service: 'configured_peer_service' } }

        it 'expects peer.service to equal configured value and source to be peer.service' do
          expect(span.get_tag('peer.service')).to eq(configuration_options[:peer_service])
          expect(span.get_tag('_dd.peer.service.source')).to eq('peer.service')
        end
      end
    end

    context 'with default peer services disabled' do
      # We still set the `peer.service` tag when it is explicitly configured

      context 'when env_var configured' do
        it 'expects peer.service to equal env var value and source to be peer.service' do
          expect(span.get_tag('peer.service')).to eq('configured_peer_service_via_env_var')
          expect(span.get_tag('_dd.peer.service.source')).to eq('peer.service')
        end
      end

      context 'when peer_service option is configured' do
        let(:configuration_options) { { peer_service: 'configured_peer_service' } }

        it 'expects peer.service to equal configured value and source to be peer.service' do
          expect(span.get_tag('peer.service')).to eq(configuration_options[:peer_service])
          expect(span.get_tag('_dd.peer.service.source')).to eq('peer.service')
        end
      end
    end
  end
end
