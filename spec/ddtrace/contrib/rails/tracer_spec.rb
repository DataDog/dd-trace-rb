require 'ddtrace/contrib/rails/rails_helper'

RSpec.describe 'Rails tracer' do
  include_context 'Rails test application'

  before { app }

  let(:config) { Datadog.configuration[:rails] }

  it 'configurations application correctly' do
    expect(app_name).to eq(config[:service_name])
    expect(config[:service_name]).to eq(config[:controller_service])
    expect("#{app_name}-cache").to eq(config[:cache_service])
    expect(Datadog.configuration[:rails][:database_service]).to be_present
    expect('views/').to eq(config[:template_base_path])
    expect(Datadog.configuration[:rails][:tracer]).to be_present
  end

  it 'sets default database' do
    expect(adapter_name).not_to eq('defaultdb')
  end
end
