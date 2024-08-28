require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/action_pack/action_dispatch/instrumentation'

require 'action_pack'
require 'action_controller/railtie'
require 'action_view/railtie'
require 'rails/test_unit/railtie'

require 'spec/datadog/tracing/contrib/rails/support/configuration'
require 'spec/datadog/tracing/contrib/rails/support/application'

RSpec.describe 'Datadog::Tracing::Contrib::ActionPack::ActionDispatch::Journey::Router' do
  let(:no_db) { true }

  include Rack::Test::Methods
  include_context 'Rails test application'

  after do
    Datadog.configuration.tracing[:action_pack].reset!
    Datadog.registry[:rack].reset_configuration!
  end

  describe '#find_routes' do
    before do
      rails_test_application.instance.routes.append do
        namespace :api, defaults: { format: :json } do
          resources :users, only: %i[show]
        end
      end
    end

    let(:controllers) { [controller] }

    let(:controller) do
      stub_const(
        'Api::UsersController',
        Class.new(ActionController::Base) do
          def show
            head :ok
          end
        end
      )
    end

    context 'with default configuration' do
      before do
        Datadog.configure do |c|
          c.tracing.instrument :rack
          c.tracing.instrument :action_pack
        end

        clear_traces!
      end

      it 'sets http.route when requesting a known route' do
        get '/api/users/1'

        rack_trace = traces.first

        expect(rack_trace.name).to eq('rack.request')
        expect(rack_trace.send(:meta).fetch('http.route')).to eq('/api/users/:id')
        expect(rack_trace.send(:meta).fetch('http.route.path')).to be_empty
      end

      it 'sets no http.route when requesting an unknown route' do
        get '/nope'

        rack_trace = traces.first

        expect(rack_trace.name).to eq('rack.request')
        expect(rack_trace.send(:meta)).not_to have_key('http.route')
        expect(rack_trace.send(:meta)).not_to have_key('http.route.path')
      end
    end

    context 'when tracing is disabled' do
      before do
        Datadog.configure do |c|
          c.tracing.enabled = false
        end

        clear_traces!
      end

      it 'does not set http.route' do
        get '/api/users/1'

        expect(traces).to be_empty
      end
    end
  end
end
