require 'rack'

require 'datadog/tracing/contrib/rack/header_tagging'

RSpec.describe Datadog::Tracing::Contrib::Rack::HeaderTagging do
  describe '.tag_response_headers' do
    before do
      Datadog.configure do |c|
        c.tracing.instrument :rack, headers: { response: ['foo'] }
      end
    end

    after { Datadog.registry[:rack].reset_configuration! }

    let(:span_op) { Datadog::Tracing::SpanOperation.new('rack.request') }
    let(:configuration) { Datadog.configuration.tracing[:rack] }

    subject(:tag_response_headers) do
      described_class.tag_response_headers(span_op, response.headers, configuration)
    end

    context 'when given a header with a single value from response headers' do
      let(:response) do
        Rack::Response.new('', 200, { 'foo' => 'bar' })
      end

      it do
        expect { tag_response_headers }.to change {
          span_op.get_tag('http.response.headers.foo')
        }.to('bar')
      end
    end

    context 'when given a header with a multiple values from response headers' do
      before do
        skip 'Rack 1.x does not support multiple header value' unless Rack::Response.new.respond_to?(:add_header)
      end

      # Rack 3.x breaking changes: Response header values can be an Array to handle multiple values
      # (and no longer supports \n encoded headers).
      #
      # Achieve compatibility by using Rack::Response#add_header
      # which provides an interface for adding headers without concern for the underlying format.
      let(:response) do
        Rack::Response.new.tap do |r|
          r.add_header('foo', 'bar')
          r.add_header('foo', 'baz')
        end
      end

      it do
        expect { tag_response_headers }.to change {
          span_op.get_tag('http.response.headers.foo')
        }.to('bar,baz')
      end
    end
  end
end
