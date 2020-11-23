require 'ddtrace/contrib/rails/rails_helper'

RSpec.describe 'Datadog::AutoInstrument' do
  include_context 'Rails test application'

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.configuration.reset!
    example.run
    Datadog.configuration.reset!
  end  

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('TEST_AUTO_INSTRUMENT').and_return(true)
    
  end

  let(:config) { Datadog.configuration[:rails] }


  it 'configurations application correctly' do
    expect_in_fork do
      app
      expect(app_name).to eq(config[:service_name])
      expect(config[:service_name]).to eq(config[:controller_service])
      expect("#{app_name}-cache").to eq(config[:cache_service])
      expect(Datadog.configuration[:rails][:database_service]).to be_present
      expect('views/').to eq(config[:template_base_path])
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
