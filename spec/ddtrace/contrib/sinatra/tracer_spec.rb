require 'spec_helper'
require 'rack/test'

require 'sinatra/base'

require 'ddtrace'
require 'ddtrace/contrib/sinatra/tracer'

RSpec.describe 'Sinatra instrumentation' do
  include Rack::Test::Methods

  let(:tracer) { get_test_tracer }
  let(:options) { { tracer: tracer } }

  let(:span) { spans.first }
  let(:spans) { tracer.writer.spans }

  before(:each) do
    Datadog.configure do |c|
      c.use :sinatra, options
    end
  end

  after(:each) { Datadog.registry[:sinatra].reset_configuration! }

  shared_context 'app with simple route' do
    let(:app) do
      Class.new(Sinatra::Application) do
        get '/' do
          'Hello, world!'
        end
      end
    end
  end

  context 'when configured' do
    context 'with default settings' do
      context 'and a simple request is made' do
        include_context 'app with simple route'

        subject(:response) { get '/' }

        it do
          is_expected.to be_ok
          expect(spans).to have(1).items

          expect(span.service).to eq(Datadog::Contrib::Sinatra::Ext::SERVICE_NAME)
          expect(span.resource).to eq('GET /')
          expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
          expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/')
          expect(span.get_tag('http.response.headers.content_type')).to eq('text/html;charset=utf-8')
          expect(span.span_type).to eq(Datadog::Ext::HTTP::TYPE)
          expect(span.status).to eq(0)
          expect(span.parent).to be nil
        end

        context 'which sets X-Request-Id on the response' do
          let(:app) do
            req_id = request_id

            Class.new(Sinatra::Application) do
              get '/' do
                headers['X-Request-Id'] = req_id
                'Hello, world!'
              end
            end
          end

          let(:request_id) { SecureRandom.uuid }

          it do
            is_expected.to be_ok
            expect(spans).to have(1).items
            expect(span.get_tag('http.response.headers.x_request_id')).to eq(request_id)
          end
        end
      end

      context 'and a request with a query string and fragment is made' do
        include_context 'app with simple route'

        subject(:response) { get '/#foo?a=1' }

        it do
          is_expected.to be_ok
          expect(spans).to have(1).items
          expect(span.resource).to eq('GET /')
          expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/')
        end
      end

      context 'and a request to a wildcard route is made' do
        let(:app) do
          Class.new(Sinatra::Application) do
            get '/*' do
              params['splat'][0]
            end
          end
        end

        subject(:response) { get '/1/2/3' }

        it do
          is_expected.to be_ok
          expect(spans).to have(1).items
          expect(span.resource).to eq('GET /*')
          expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/1/2/3')
        end
      end

      context 'and a request to a template route is made' do
        let(:app) do
          Class.new(Sinatra::Application) do
            get '/' do
              erb :msg, locals: { msg: 'hello' }
            end
          end
        end

        subject(:response) { get '/' }

        let(:parent_span) { spans[2] }
        let(:child_span) { spans[0] }
        let(:grandchild_span) { spans[1] }

        before(:each) do
          expect(response).to be_ok
          expect(spans).to have(3).items
        end

        describe 'the sinatra.request span' do
          subject(:span) { parent_span }

          it do
            expect(span.name).to eq(Datadog::Contrib::Sinatra::Ext::SPAN_REQUEST)
            expect(span.resource).to eq('GET /')
            expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/')
            expect(span.parent).to be nil
          end
        end

        describe 'the sinatra.render_template child span' do
          subject(:span) { child_span }

          it do
            expect(span.name).to eq(Datadog::Contrib::Sinatra::Ext::SPAN_RENDER_TEMPLATE)
            expect(span.resource).to eq('sinatra.render_template')
            expect(span.get_tag('sinatra.template_name')).to eq('msg')
            expect(span.parent).to eq(parent_span)
          end
        end

        describe 'the sinatra.render_template grandchild span' do
          subject(:span) { grandchild_span }

          it do
            expect(span.name).to eq(Datadog::Contrib::Sinatra::Ext::SPAN_RENDER_TEMPLATE)
            expect(span.resource).to eq('sinatra.render_template')
            expect(span.get_tag('sinatra.template_name')).to eq('layout')
            expect(span.parent).to eq(child_span)
          end
        end
      end

      context 'and a request to a literal template route is made' do
        let(:app) do
          Class.new(Sinatra::Application) do
            get '/' do
              erb '<%= msg %>', locals: { msg: 'hello' }
            end
          end
        end

        subject(:response) { get '/' }

        let(:parent_span) { spans[2] }
        let(:child_span) { spans[0] }
        let(:grandchild_span) { spans[1] }

        before(:each) do
          expect(response).to be_ok
          expect(spans).to have(3).items
        end

        describe 'the sinatra.request span' do
          subject(:span) { parent_span }

          it do
            expect(span.name).to eq(Datadog::Contrib::Sinatra::Ext::SPAN_REQUEST)
            expect(span.resource).to eq('GET /')
            expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/')
            expect(span.parent).to be nil
          end
        end

        describe 'the sinatra.render_template child span' do
          subject(:span) { child_span }

          it do
            expect(span.name).to eq(Datadog::Contrib::Sinatra::Ext::SPAN_RENDER_TEMPLATE)
            expect(span.resource).to eq('sinatra.render_template')
            expect(span.get_tag('sinatra.template_name')).to be nil
            expect(span.parent).to eq(parent_span)
          end
        end

        describe 'the sinatra.render_template grandchild span' do
          subject(:span) { grandchild_span }

          it do
            expect(span.name).to eq(Datadog::Contrib::Sinatra::Ext::SPAN_RENDER_TEMPLATE)
            expect(span.resource).to eq('sinatra.render_template')
            expect(span.get_tag('sinatra.template_name')).to eq('layout')
            expect(span.parent).to eq(child_span)
          end
        end
      end

      context 'and a bad request is made' do
        let(:app) do
          Class.new(Sinatra::Application) do
            get '/' do
              halt 400, 'bad request'
            end
          end
        end

        subject(:response) { get '/' }

        it do
          is_expected.to be_bad_request
          expect(spans).to have(1).items
          expect(span.get_tag(Datadog::Ext::Errors::TYPE)).to be nil
          expect(span.get_tag(Datadog::Ext::Errors::MSG)).to be nil
          expect(span.status).to eq(0)
        end
      end

      context 'and a request resulting in an internal error is made' do
        let(:app) do
          Class.new(Sinatra::Application) do
            get '/' do
              halt 500, 'server error'
            end
          end
        end

        subject(:response) { get '/' }

        it do
          is_expected.to be_server_error
          expect(spans).to have(1).items
          expect(span.get_tag(Datadog::Ext::Errors::TYPE)).to be nil
          expect(span.get_tag(Datadog::Ext::Errors::MSG)).to be nil
          expect(span.status).to eq(1)
        end
      end

      context 'and a request that raises an exception is made' do
        let(:app) do
          Class.new(Sinatra::Application) do
            get '/' do
              raise StandardError, 'something bad'
            end
          end
        end

        subject(:response) { get '/' }

        it do
          is_expected.to be_server_error
          expect(spans).to have(1).items
          expect(span.get_tag(Datadog::Ext::Errors::TYPE)).to eq('StandardError')
          expect(span.get_tag(Datadog::Ext::Errors::MSG)).to eq('something bad')
          expect(span.status).to eq(1)
        end
      end
    end

    context 'with a custom service name' do
      let(:options) { super().merge(service_name: service_name) }
      let(:service_name) { 'my-sinatra-app' }

      context 'and a simple request is made' do
        include_context 'app with simple route'

        subject(:response) { get '/' }

        it do
          is_expected.to be_ok
          expect(spans).to have(1).items
          expect(span.service).to eq(service_name)
        end
      end
    end

    context 'with distributed tracing' do
      let(:options) { super().merge(distributed_tracing: true) }

      context 'and a simple request is made' do
        include_context 'app with simple route'

        subject(:response) { get '/', query_string, headers }
        let(:query_string) { {} }
        let(:headers) { {} }

        context 'with distributed tracing headers' do
          let(:headers) do
            {
              'HTTP_X_DATADOG_TRACE_ID' => '1',
              'HTTP_X_DATADOG_PARENT_ID' => '2',
              'HTTP_X_DATADOG_SAMPLING_PRIORITY' => Datadog::Ext::Priority::USER_KEEP.to_s
            }
          end

          it do
            is_expected.to be_ok
            expect(spans).to have(1).items
            expect(span.trace_id).to eq(1)
            expect(span.parent_id).to eq(2)
            expect(span.get_metric(Datadog::Ext::DistributedTracing::SAMPLING_PRIORITY_KEY)).to eq(2.0)
          end
        end
      end
    end

    context 'with header tags' do
      let(:options) { super().merge(headers: { request: request_headers, response: response_headers }) }
      let(:request_headers) { [] }
      let(:response_headers) { [] }

      context 'and a simple request is made' do
        include_context 'app with simple route'

        subject(:response) { get '/', query_string, headers }
        let(:query_string) { {} }
        let(:headers) { {} }

        context 'with a header that should be tagged' do
          let(:request_headers) { ['X-Request-Header'] }
          let(:headers) { { 'HTTP_X_REQUEST_HEADER' => header_value } }
          let(:header_value) { SecureRandom.uuid }

          it do
            is_expected.to be_ok
            expect(spans).to have(1).items
            expect(span.get_tag('http.request.headers.x_request_header')).to eq(header_value)
          end
        end

        context 'with a header that should not be tagged' do
          let(:headers) { { 'HTTP_X_REQUEST_HEADER' => header_value } }
          let(:header_value) { SecureRandom.uuid }

          it do
            is_expected.to be_ok
            expect(spans).to have(1).items
            expect(span.get_tag('http.request.headers.x_request_header')).to be nil
          end
        end
      end
    end

    context 'with script names' do
      let(:options) { super().merge(resource_script_names: true) }

      let(:app) do
        Class.new(Sinatra::Application) do
          get '/endpoint' do
            '1'
          end
        end
      end

      subject(:response) { get '/endpoint' }

      it do
        is_expected.to be_ok
        expect(spans).to have(1).items
        expect(span.resource).to eq('GET /endpoint')
      end
    end
  end

  context 'when the tracer is disabled' do
    include_context 'app with simple route'

    subject(:response) { get '/' }
    let(:tracer) { get_test_tracer(enabled: false) }

    it do
      is_expected.to be_ok
      expect(spans).to be_empty
    end
  end
end
