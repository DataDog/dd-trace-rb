require 'ddtrace/contrib/support/spec_helper'

require 'rack'
require 'ddtrace'
require 'ddtrace/contrib/rack/middlewares'

RSpec.describe Datadog::Contrib::Rack::TraceMiddleware do
  subject(:middleware) { described_class.new(app) }

  let(:app) { instance_double(Rack::Builder) }

  let(:configuration_options) { {} }

  before do
    Datadog.configure do |c|
      c.use :rack, configuration_options
    end
  end

  describe '#call' do
    subject(:middleware_call) { middleware.call(env) }

    let(:env) { { 'rack.url_scheme' => 'http' } } # Scheme necessary for Rack 1.4.7
    let(:response) { [200, { 'Content-Type' => 'text/plain' }, ['OK']] }

    before do
      allow(app).to receive(:call)
        .with(env)
        .and_return(response)
    end

    describe 'deprecation warnings' do
      before { allow(Datadog.logger).to receive(:warn) }

      # Expect this for backwards compatibility
      context 'backwards compatibility' do
        before { middleware_call }

        it do
          expect(env).to include(
            datadog_rack_request_span: kind_of(Datadog::Span),
            'datadog.rack_request_span' => kind_of(Datadog::Span)
          )
        end
      end

      context 'when :datadog_rack_request_span is accessed on the span' do
        before do
          allow(app).to receive(:call).with(env) do |env|
            # Trigger deprecation warning
            env[:datadog_rack_request_span]
            response
          end

          middleware_call
        end

        it do
          expect(Datadog.logger).to_not have_received(:warn)
            .with(/:datadog_rack_request_span/)
        end
      end

      context 'when the same Rack env object is run twice' do
        before do
          middleware.call(env)
          middleware.call(env)
        end

        it do
          expect(Datadog.logger).to_not have_received(:warn)
            .with(/:datadog_rack_request_span/)
        end
      end
    end

    context 'with fatal exception' do
      let(:fatal_error) { stub_const('FatalError', Class.new(RuntimeError)) }

      before do
        # Raise error at first line of #call
        expect(Datadog.configuration[:rack]).to receive(:[]).and_raise(fatal_error)
      end

      it 'reraises exception' do
        expect { middleware_call }.to raise_error(fatal_error)
      end
    end
  end
end
