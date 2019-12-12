require 'ddtrace/contrib/rails/rails_helper'

RSpec.describe 'Rails middleware' do
  include Rack::Test::Methods
  include_context 'Rails test application'

  let(:routes) { { '/' => 'test#index' } }
  let(:controllers) { [controller] }

  let(:controller) do
    stub_const('TestController', Class.new(ActionController::Base) do
      def index
        head :ok
      end
    end)
  end

  RSpec::Matchers.define :have_kind_of_middleware do |expected|
    match do |actual|
      while actual
        return true if actual.class <= expected
        without_warnings { actual = actual.instance_variable_get(:@app) }
      end
      false
    end
  end

  before do
    Datadog.configure do |c|
      c.use :rack if use_rack
      c.use :rails, rails_options
    end
  end

  let(:use_rack) { true }
  let(:rails_options) { {} }

  context 'with middleware' do
    context 'that does nothing' do
      let(:middleware) do
        stub_const('PassthroughMiddleware', Class.new do
          def initialize(app)
            @app = app
          end

          def call(env)
            @app.call(env)
          end
        end)
      end

      context 'and added after tracing is enabled' do
        before do
          passthrough_middleware = middleware
          rails_test_application.configure { config.app_middleware.use passthrough_middleware }
        end

        context 'with #middleware_names' do
          let(:use_rack) { false }
          let(:rails_options) { super().merge!(middleware_names: true) }

          it do
            get '/'
            expect(app).to have_kind_of_middleware(middleware)
            expect(last_response).to be_ok
          end
        end
      end
    end

    context 'that itself creates a span' do
      let(:middleware) do
        stub_const('CustomSpanMiddleware', Class.new do
          def initialize(app)
            @app = app
          end

          def call(env)
            Datadog.tracer.trace('custom.test') do
              @app.call(env)
            end
          end
        end)
      end

      context 'and added after tracing is enabled' do
        before do
          custom_span_middleware = middleware
          rails_test_application.configure { config.app_middleware.use custom_span_middleware }
        end

        context 'with #middleware_names' do
          let(:use_rack) { false }
          let(:rails_options) { super().merge!(middleware_names: true) }

          it do
            get '/'
            span = spans.find { |s| s.name == 'rack.request' }
            expect(span.resource).to eq('TestController#index')
          end
        end
      end
    end

    context 'that raises an exception' do
      before { get '/' }

      let(:rails_middleware) { [middleware] }
      let(:middleware) do
        stub_const('RaiseExceptionMiddleware', Class.new do
          def initialize(app)
            @app = app
          end

          def call(env)
            @app.call(env)
            raise NotImplementedError
          end
        end)
      end

      it do
        expect(app).to have_kind_of_middleware(middleware)
        expect(last_response).to be_server_error
        expect(spans).to have_at_least(2).items
      end

      context 'rack span' do
        subject(:span) { spans.first }

        it do
          expect(span.name).to eq('rack.request')
          expect(span.span_type).to eq('web')
          expect(span.resource).to eq('TestController#index')
          expect(span.get_tag('http.url')).to eq('/')
          expect(span.get_tag('http.method')).to eq('GET')
          expect(span.get_tag('http.status_code')).to eq('500')
          expect(span.get_tag('error.type')).to eq('NotImplementedError')
          expect(span.get_tag('error.msg')).to eq('NotImplementedError')
          expect(span).to have_error
          expect(span.get_tag('error.stack')).to_not be nil
        end
      end
    end

    context 'that raises a known NotFound exception' do
      before { get '/' }

      let(:rails_middleware) { [middleware] }
      let(:middleware) do
        stub_const('RaiseNotFoundMiddleware', Class.new do
          def initialize(app)
            @app = app
          end

          def call(env)
            @app.call(env)
            raise ActionController::RoutingError, '/missing_route'
          end
        end)
      end

      it do
        expect(app).to have_kind_of_middleware(middleware)
        expect(last_response).to be_not_found
        expect(spans).to have_at_least(2).items
      end

      context 'rack span' do
        subject(:span) { spans.first }

        it do
          expect(span.name).to eq('rack.request')
          expect(span.span_type).to eq('web')
          expect(span.resource).to eq('TestController#index')
          expect(span.get_tag('http.url')).to eq('/')
          expect(span.get_tag('http.method')).to eq('GET')
          expect(span.get_tag('http.status_code')).to eq('404')

          if Rails.version >= '3.2'
            expect(span.get_tag('error.type')).to be nil
            expect(span.get_tag('error.msg')).to be nil
            expect(span).to_not have_error
            expect(span.get_tag('error.stack')).to be nil
          else
            # Rails 3.0 raises errors for 404 routing errors
            expect(span.get_tag('error.type')).to eq('ActionController::RoutingError')
            expect(span.get_tag('error.msg')).to eq('/missing_route')
            expect(span).to have_error
            expect(span.get_tag('error.stack')).to_not be nil
          end
        end
      end
    end

    context 'that raises a custom exception' do
      before { get '/' }

      let(:rails_middleware) { [middleware] }
      let(:error_class) do
        stub_const('CustomError', Class.new(StandardError) do
          def message
            'Custom error message!'
          end
        end)
      end

      let(:middleware) do
        # Run this to define the error class
        error_class

        stub_const('RaiseCustomErrorMiddleware', Class.new do
          def initialize(app)
            @app = app
          end

          def call(env)
            @app.call(env)
            raise CustomError
          end
        end)
      end

      it do
        expect(app).to have_kind_of_middleware(middleware)
        expect(last_response).to be_server_error
        expect(spans).to have_at_least(2).items
      end

      context 'rack span' do
        subject(:span) { spans.first }

        it do
          expect(span.name).to eq('rack.request')
          expect(span.span_type).to eq('web')
          expect(span.resource).to eq('TestController#index')

          expect(span.get_tag('http.url')).to eq('/') if Rails.version >= '3.2'

          expect(span.get_tag('http.method')).to eq('GET')
          expect(span.get_tag('http.status_code')).to eq('500')
          expect(span.get_tag('error.type')).to eq('CustomError')
          expect(span.get_tag('error.msg')).to eq('Custom error message!')
          expect(span).to have_error
          expect(span.get_tag('error.stack')).to_not be nil
        end
      end

      if Rails.version >= '3.2'
        context 'that is flagged as a custom 404' do
          # TODO: Make a cleaner API for injecting into Rails application configuration
          let(:initialize_block) do
            super_block = super()
            proc do
              instance_exec(&super_block)
              config.action_dispatch.rescue_responses.merge!(
                'CustomError' => :not_found
              )
            end
          end

          after do
            # Be sure to delete configuration after, so it doesn't carry over to other examples.
            # TODO: Clear this configuration automatically via rails_helper shared examples
            ActionDispatch::Railtie.config.action_dispatch.rescue_responses.delete('CustomError')
            ActionDispatch::ExceptionWrapper.class_variable_get(:@@rescue_responses).tap do |resps|
              resps.delete('CustomError')
            end
          end

          it do
            expect(app).to have_kind_of_middleware(middleware)
            expect(last_response).to be_not_found
            expect(spans).to have_at_least(2).items
          end

          context 'rack span' do
            subject(:span) { spans.first }

            it do
              expect(span.name).to eq('rack.request')
              expect(span.span_type).to eq('web')
              expect(span.resource).to eq('TestController#index')
              expect(span.get_tag('http.url')).to eq('/')
              expect(span.get_tag('http.method')).to eq('GET')
              expect(span.get_tag('http.status_code')).to eq('404')
              expect(span.get_tag('error.type')).to be nil
              expect(span.get_tag('error.msg')).to be nil
              expect(span).to_not have_error
              expect(span.get_tag('error.stack')).to be nil
            end
          end
        end
      end
    end
  end
end
