RSpec.shared_examples_for 'environment service name' do |env_service_name_key, error: nil|
  context "when given `#{env_service_name_key}` environment variable" do
    around do |example|
      ClimateControl.modify(env_service_name_key => 'environment_default') do
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

    context 'when none configured' do
      it { expect(span.service).to eq('environment_default') }
    end

    context 'when given service_name' do
      let(:configuration_options) { { service_name: 'configured' } }

      it { expect(span.service).to eq(configuration_options[:service_name]) }
    end
  end
end
