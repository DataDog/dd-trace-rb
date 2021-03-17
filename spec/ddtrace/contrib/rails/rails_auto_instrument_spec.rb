require 'ddtrace/contrib/rails/rails_helper'

RSpec.describe 'Datadog::Contrib::AutoInstrument' do
  include_context 'Rails test application'

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.configuration.reset!

    ClimateControl.modify('TEST_AUTO_INSTRUMENT' => 'true') do
      example.run
    end

    Datadog.configuration.reset!
  end

  context 'when auto patching is included' do
    before do
      skip 'Fork not supported on current platform' unless Process.respond_to?(:fork)
    end

    let(:config) { Datadog.configuration[:rails] }

    it 'configurations application correctly' do
      expect_in_fork do
        app
        expect(app_name).to eq(config[:service_name])
        expect(config[:service_name]).to eq(config[:controller_service])
        expect("#{app_name}-cache").to eq(config[:cache_service])
        expect(Datadog.configuration[:rails][:database_service]).to be_present
        expect(config[:template_base_path]).to eq('views/')
        expect(Datadog.configuration[:rails][:tracer]).to be_present
      end
    end

    it 'sets default database' do
      expect_in_fork do
        app
        expect(adapter_name).not_to eq('defaultdb')
      end
    end
  end
end
