require 'ddtrace/contrib/rails/rails_helper'

RSpec.describe 'Rails Rack Rum Injection middleware' do
  include Rack::Test::Methods
  include_context 'Rails test application'

  let(:routes) { { '/' => 'test#index' } }
  let(:controllers) { [controller] }

  let(:controller) do
    stub_const('TestController', Class.new(ActionController::Base) do
      def index
        response.headers['Cache-Control'] = 'max-age=0'
        render inline: '<html> <head> </head> <body> <div> Hello from index </div> </body> </html>'
      end
    end)
  end

  before do
    Datadog.configuration[:rack].reset_options!
    Datadog.configuration[:rails].reset_options!

    Datadog.configure do |c|
      c.use :rack, rum_injection_enabled: true
      c.use :rails
    end
  end

  after do
    Datadog.configuration[:rack].reset_options!
    Datadog.configuration[:rails].reset_options!
  end

  context 'with RumInjection middleware' do
    context 'injects rum related trace_id when enabled' do
      before { get '/' }

      it 'should inject trace_id into html response' do
        expect(last_response.body).to include(spans[0].trace_id.to_s)
      end
    end
  end
end
