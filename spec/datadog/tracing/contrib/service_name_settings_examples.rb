RSpec.shared_examples 'service name setting' do |default_service_name_v0|
  describe 'Option `service_name`' do
    context 'when with service_name' do # default to include base
      it do
        expect(described_class.new(service_name: 'test-service').service_name).to eq('test-service')
      end
    end

    context 'when without service_name v0' do # default to include base
      it do
        expect(described_class.new.service_name).to eq(default_service_name_v0)
      end
    end

    context 'when without service_name v0 but uses env var' do
      with_env DD_TRACE_REMOVE_INTEGRATION_SERVICE_NAMES_ENABLED: 'true'

      it do
        expect(described_class.new.service_name).to eq('rspec')
      end
    end
  end
end
