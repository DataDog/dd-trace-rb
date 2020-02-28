require 'spec_helper'

require 'rack'
require 'ddtrace'
require 'ddtrace/contrib/rack/middlewares'

RSpec.describe Datadog::Contrib::Rack::TraceMiddleware do
  subject(:middleware) { described_class.new(app) }
  let(:app) { instance_double(Rack::Builder) }

  let(:tracer) { get_test_tracer }
  let(:configuration_options) { { tracer: tracer } }

  before(:each) do
    Datadog.configure do |c|
      c.use :rack, configuration_options
    end
  end

  describe '#call' do
    subject(:middleware_call) { middleware.call(env) }
    let(:env) { { 'rack.url_scheme' => 'http' } } # Scheme necessary for Rack 1.4.7
    let(:response) { [200, { 'Content-Type' => 'text/plain' }, ['OK']] }

    before(:each) do
      allow(app).to receive(:call)
        .with(env)
        .and_return(response)
    end

    describe 'deprecation warnings' do
      before(:each) { allow(Datadog::Logger.log).to receive(:warn) }

      # Expect this for backwards compatibility
      context 'backwards compatibility' do
        before(:each) { middleware_call }

        it do
          expect(env).to include(
            datadog_rack_request_span: kind_of(Datadog::Span),
            'datadog.rack_request_span' => kind_of(Datadog::Span)
          )
        end
      end

      context 'when :datadog_rack_request_span is accessed on the span' do
        before(:each) do
          allow(app).to receive(:call).with(env) do |env|
            # Trigger deprecation warning
            env[:datadog_rack_request_span]
            response
          end

          middleware_call
        end

        it do
          expect(Datadog::Logger.log).to_not have_received(:warn)
            .with(/:datadog_rack_request_span/)
        end
      end

      context 'when the same Rack env object is run twice' do
        before(:each) do
          middleware.call(env)
          middleware.call(env)
        end

        it do
          expect(Datadog::Logger.log).to_not have_received(:warn)
            .with(/:datadog_rack_request_span/)
        end
      end
    end
  end
end
