require 'datadog/tracing/contrib/rails/rails_helper'

RSpec.describe 'Rails tracer' do
  include_context 'Rails test application'

  before { app }

  let(:config) { Datadog.configuration.tracing[:rails] }

  it 'configurations application correctly' do
    expect(config[:template_base_path]).to eq('views/')
  end

  it 'sets default database' do
    expect(adapter_name).not_to eq('defaultdb')
  end
end
