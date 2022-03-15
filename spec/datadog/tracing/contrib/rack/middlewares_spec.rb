# typed: ignore

require 'datadog/tracing/contrib/support/spec_helper'

require 'rack'
require 'ddtrace'
require 'datadog/tracing/contrib/rack/middlewares'

RSpec.describe Datadog::Tracing::Contrib::Rack::TraceMiddleware do
  subject(:middleware) { described_class.new(app) }

  let(:app) { instance_double(Rack::Builder) }

  let(:configuration_options) { {} }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :rack, configuration_options
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

    context 'with fatal exception' do
      let(:fatal_error) { stub_const('FatalError', Class.new(RuntimeError)) }

      before do
        # Raise error at first line of #call
        expect(Datadog.configuration.tracing[:rack]).to receive(:[]).and_raise(fatal_error)
      end

      it 'reraises exception' do
        expect { middleware_call }.to raise_error(fatal_error)
      end
    end
  end
end
