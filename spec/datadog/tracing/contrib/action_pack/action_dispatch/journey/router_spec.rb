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

  describe '#serve' do
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

        rack_span = spans.first

        expect(rack_span).to be_root_span
        expect(rack_span.name).to eq('rack.request')

        expect(rack_span.get_tag('http.route')).to eq('/api/users/:id')
      end

      it 'sets no http.route when requesting an unknown route' do
        get '/nope'

        rack_span = spans.first

        expect(rack_span).to be_root_span
        expect(rack_span.name).to eq('rack.request')

        expect(rack_span.tags).not_to have_key('http.route')
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

        expect(spans).to be_empty
      end
    end
  end
end
