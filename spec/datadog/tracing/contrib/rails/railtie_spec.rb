require 'datadog/tracing/contrib/rails/rails_helper'
require 'datadog/tracing/contrib/rails/framework'
require 'datadog/tracing/contrib/rails/middlewares'
require 'datadog/tracing/contrib/rack/middlewares'

RSpec.describe 'Rails Railtie' do
  before { skip 'Test not compatible with Rails < 4.0' if Rails.version < '4.0' }

  include_context 'Rails test application'

  let(:routes) { { '/' => 'test#index' } }
  let(:rails_options) { {} }
  let(:controllers) { [controller] }

  let(:controller) do
    stub_const(
      'TestController',
      Class.new(ActionController::Base) do
        def index
          head :ok
        end
      end
    )
  end

  RSpec::Matchers.define :have_kind_of_middleware do |expected|
    match do |actual|
      found = 0
      while actual
        found += 1 if actual.class <= expected
        without_warnings { actual = actual.instance_variable_get(:@app) }
      end
      found == (count || 1)
    end

    chain :once do
      @count = 1
    end

    chain :copies, :count
  end

  before do
    Datadog.configure do |c|
      c.tracing.instrument :rails, rails_options
    end
  end

  describe 'with Rails integration #middleware option' do
    context 'set to true' do
      let(:rails_options) { super().merge(middleware: true) }

      it { expect(app).to have_kind_of_middleware(Datadog::Tracing::Contrib::Rack::TraceMiddleware).once }
      it { expect(app).to have_kind_of_middleware(Datadog::Tracing::Contrib::Rails::ExceptionMiddleware).once }
    end

    context 'set to false' do
      let(:rails_options) { super().merge(middleware: false) }

      after { Datadog.configuration.tracing[:rails][:middleware] = true }

      it { expect(app).to_not have_kind_of_middleware(Datadog::Tracing::Contrib::Rack::TraceMiddleware) }
      it { expect(app).to_not have_kind_of_middleware(Datadog::Tracing::Contrib::Rails::ExceptionMiddleware) }
    end
  end

  describe 'when load hooks run twice' do
    subject! do
      # Set expectations
      expect(Datadog::Tracing::Contrib::Rails::Patcher).to receive(:add_middleware)
        .with(a_kind_of(Rails::Application))
        .once
        .and_call_original

      without_warnings do
        # Then load the app, which run load hooks
        app

        # Then manually re-run load hooks
        ActiveSupport.run_load_hooks(:before_initialize, app)
        ActiveSupport.run_load_hooks(:after_initialize, app)
      end
    end

    it 'only includes the middleware once' do
      expect(app).to have_kind_of_middleware(Datadog::Tracing::Contrib::Rack::TraceMiddleware).once
      expect(app).to have_kind_of_middleware(Datadog::Tracing::Contrib::Rails::ExceptionMiddleware).once
    end
  end
end
