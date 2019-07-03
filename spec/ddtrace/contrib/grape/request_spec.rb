require 'spec_helper'
require 'rack/test'
require 'grape'
require 'ddtrace'

RSpec.describe 'Request tracing' do
  include Rack::Test::Methods

  let(:tracer) { get_test_tracer }
  let(:options) { { tracer: tracer } }
  let(:app) do
    Class.new(Grape::API) do
      namespace :base do
        get :only_get_request do
          'OK'
        end
      end
    end
  end

  before(:each) do
    Datadog.configure do |c|
      c.use :grape, options
    end
  end

  after(:each) { Datadog.registry[:grape].reset_configuration! }

  it 'reports 405 as an error' do
    post '/base/only_get_request'

    expect(tracer.writer.spans()[0].status).to eq(1)
  end

  context 'when 4xx is excluded from errors' do
    let(:options) { { tracer: tracer, error_for_4xx: false } }

    it 'does not report 405 as an error' do
      post '/base/only_get_request'

      expect(tracer.writer.spans()[0].status).to eq(0)
    end
  end
end
