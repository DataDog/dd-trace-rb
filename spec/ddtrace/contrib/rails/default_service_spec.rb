require 'ddtrace/contrib/rails/rails_helper'

RSpec.describe 'Default service' do
  include_context 'Rails test application'
  include_context 'Tracer'

  before { app } # Force Rails initialization

  subject(:response) { get '/', {}, headers }

  before do
    @original_tracer = Datadog.configuration[:rails][:tracer]
    Datadog.configuration[:rails][:tracer] = tracer
    update_config(:tracer, tracer)
  end

  after do
    Datadog.configuration[:rails][:tracer] = @original_tracer
  end

  it 'span has rails service' do
    # Manually creating the span and forgetting service on purpose
    tracer.trace('web.request') do |span|
      span.resource = '/index'
    end

    expect(spans).to have(1).item

    expect(span.name).to eq('web.request')
    expect(span.resource).to eq('/index')
    expect(span.service).to eq(app_name)
  end
end
