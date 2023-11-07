require 'datadog/tracing/contrib/support/spec_helper'

require 'action_controller'

require 'ddtrace'
require 'datadog/tracing/contrib/action_pack/action_controller/instrumentation'

RSpec.describe 'Datadog::Tracing::Contrib::ActionPack::ActionController::Metal' do
  include Rack::Test::Methods

  describe '#process_action' do
    context 'with ErrorController' do
      after do
        Datadog.configuration.tracing[:action_pack].reset!
        Datadog.registry[:rack].reset_configuration!
      end

      let(:exception_controller_class) do
        stub_const(
          'ErrorController',
          Class.new(ActionController::Base) do
            def handle_error
              head :ok
            end
          end
        )
      end

      let(:controller_class) do
        stub_const(
          'TestController',
          Class.new(ActionController::Base) do
            def test
              head :ok
            end

            def raise_exception
              raise StandardError, 'bala boom!'
            end
          end
        )
      end

      let(:app) do
        test_action = controller_class.action(:test)
        error_action = controller_class.action(:raise_exception)
        error_handler = exception_controller_class.action(:handle_error)

        # This app mimic the middleware stack of Rails on Rack,
        # use ActionDispatch::ShowExceptions to render exception with error handler
        #
        # The trace with `/boom` looks like:
        # ================================ rack.request =================================
        #       === rails.action_controller ===       === rails.action_controller ===
        #       (TestController#raise_exception)       (ErrorController#handle_error)

        Rack::Builder.app do
          use Datadog::Tracing::Contrib::Rack::TraceMiddleware
          use ActionDispatch::ShowExceptions, error_handler

          map '/test' do
            run test_action
          end

          map '/boom' do
            run error_action
          end

          map '/error_handler' do
            run error_handler
          end
        end
      end

      context 'ErrorController' do
        context 'when default configuration' do
          before do
            Datadog.configure do |c|
              c.tracing.instrument :rack
              c.tracing.instrument :action_pack
            end
          end

          context 'when given a request to test endpoint' do
            it 'renders within TestController' do
              get '/test'

              expect(spans).to have(2).items

              rack_span, controller_span = spans

              expect(rack_span).to be_root_span
              expect(rack_span.name).to eq('rack.request')
              expect(rack_span.resource).to eq('TestController#test')

              expect(controller_span.parent_id).to eq(rack_span.id)
              expect(controller_span.name).to eq('rails.action_controller')
              expect(controller_span.resource).to eq('TestController#test')
              expect(controller_span.get_tag('component')).to eq('action_pack')
              expect(controller_span.get_tag('operation')).to eq('controller')
              expect(controller_span.get_tag('rails.route.controller')).to eq('TestController')
              expect(controller_span.get_tag('rails.route.action')).to eq('test')
            end
          end

          context 'when given a request that raise exception' do
            it 'renders the exception with error handler' do
              get '/boom'

              expect(spans).to have(3).items

              rack_span, handle_err_span, controller_span = spans

              expect(rack_span).to be_root_span
              expect(rack_span.name).to eq('rack.request')
              expect(rack_span.resource).to eq('TestController#raise_exception')
              expect(rack_span).to_not have_error

              expect(handle_err_span.parent_id).to eq(rack_span.id)
              expect(handle_err_span.name).to eq('rails.action_controller')
              expect(handle_err_span.resource).to eq('ErrorController#handle_error')
              expect(handle_err_span.get_tag('component')).to eq('action_pack')
              expect(handle_err_span.get_tag('operation')).to eq('controller')
              expect(handle_err_span.get_tag('rails.route.controller')).to eq('ErrorController')
              expect(handle_err_span.get_tag('rails.route.action')).to eq('handle_error')
              expect(handle_err_span).to_not have_error

              expect(controller_span.parent_id).to eq(rack_span.id)
              expect(controller_span.name).to eq('rails.action_controller')
              expect(controller_span.resource).to eq('TestController#raise_exception')
              expect(controller_span.get_tag('component')).to eq('action_pack')
              expect(controller_span.get_tag('operation')).to eq('controller')
              expect(controller_span.get_tag('rails.route.controller')).to eq('TestController')
              expect(controller_span.get_tag('rails.route.action')).to eq('raise_exception')
              expect(controller_span).to have_error
            end
          end

          context 'when given a request to error handling endpoint' do
            it 'renders within ErrorController' do
              get '/error_handler'

              expect(spans).to have(2).items

              rack_span, handle_err_span = spans

              expect(rack_span).to be_root_span
              expect(rack_span.name).to eq('rack.request')
              expect(rack_span.resource).to eq('ErrorController#handle_error')

              expect(handle_err_span.parent_id).to eq(rack_span.id)
              expect(handle_err_span.name).to eq('rails.action_controller')
              expect(handle_err_span.resource).to eq('ErrorController#handle_error')
              expect(handle_err_span.get_tag('component')).to eq('action_pack')
              expect(handle_err_span.get_tag('operation')).to eq('controller')
              expect(handle_err_span.get_tag('rails.route.controller')).to eq('ErrorController')
              expect(handle_err_span.get_tag('rails.route.action')).to eq('handle_error')
            end
          end

          context 'when given a request to error handling endpoint with ActionDispatch exception' do
            it 'renders within ErrorController and does not change trace resource' do
              get '/error_handler', {}, 'action_dispatch.exception' => ArgumentError.new

              expect(spans).to have(2).items

              rack_span, handle_err_span = spans

              expect(rack_span).to be_root_span
              expect(rack_span.name).to eq('rack.request')
              expect(rack_span.resource).to eq('GET 200')

              expect(handle_err_span.parent_id).to eq(rack_span.id)
              expect(handle_err_span.name).to eq('rails.action_controller')
              expect(handle_err_span.resource).to eq('ErrorController#handle_error')
              expect(handle_err_span.get_tag('component')).to eq('action_pack')
              expect(handle_err_span.get_tag('operation')).to eq('controller')
              expect(handle_err_span.get_tag('rails.route.controller')).to eq('ErrorController')
              expect(handle_err_span.get_tag('rails.route.action')).to eq('handle_error')
            end
          end
        end
      end
    end
  end
end
