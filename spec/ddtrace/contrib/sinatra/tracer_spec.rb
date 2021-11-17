# typed: ignore
require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/contrib/analytics_examples'
require 'rack/test'

require 'sinatra/base'

require 'ddtrace'
require 'ddtrace/contrib/sinatra/tracer'

require 'rspec/expectations'

RSpec.describe 'Sinatra instrumentation' do
  include Rack::Test::Methods

  subject(:response) { get url }

  let(:configuration_options) { {} }
  let(:url) { '/' }
  let(:http_method) { 'GET' }
  let(:resource) { "#{http_method} #{url}" }
  let(:observed) { {} }
  let(:sinatra_routes) do
    observed = self.observed
    lambda do
      get '/' do
        headers['X-Request-ID'] = 'test id'
        'ok'
      end

      get '/wildcard/*' do
        params['splat'][0]
      end

      get '/error' do
        raise 'test error'
      end

      get '/client_error' do
        halt 400, 'bad request'
      end

      get '/server_error' do
        halt 500, 'server error'
      end

      get '/erb' do
        headers['Cache-Control'] = 'max-age=0'

        erb :msg, locals: { msg: 'hello' }
      end

      get '/erb_manual_injection' do
        headers['Cache-Control'] = 'max-age=0'

        erb :msg_manual_injection, locals: { msg: 'hello' }
      end

      get '/erb_manual_injection_no_env' do
        headers['Cache-Control'] = 'max-age=0'

        erb :msg_manual_injection_no_env, locals: { msg: 'hello' }
      end

      get '/erb_literal' do
        erb '<%= msg %>', locals: { msg: 'hello' }
      end

      get '/span_resource' do
        active_span = Datadog.tracer.active_span
        observed[:active_span] = { name: active_span.name, resource: active_span.resource }

        chain = lambda { |start| loop.with_object([start]) { |_, o| break o if o.last.parent.nil?; o << o.last.parent } }
        spans = chain.call(active_span)
        observed[:spans] = spans

        # Sinatra doesn't know which route will match /span_resource , thus
        # having to scan linearly all the registered routes.  When it scans in
        # this example, it passes over all routes for NestedApp, as they were
        # registered first, but does not hit a route in the nested app.  It
        # then finds /span_resource at the root app App, which were registered
        # later than the nested app routes.
        #
        # Thus active_span.parent can refer to a Sinatra span from NestedApp,
        # nested behind a Rack span and then only Sinatra+Rack spans from App,
        # so we find the first Sinatra elder span that has a resource.
        sinatra_request_span = spans.find { |x| !x.resource.nil? && x.name == Datadog::Contrib::Sinatra::Ext::SPAN_REQUEST }
        observed[:sinatra_request_span] = { name: sinatra_request_span.name, resource: sinatra_request_span.resource }

        'ok'
      end
    end
  end

  let(:sorted_spans) do
    chain = lambda { |start| loop.with_object([start]) { |_, o| break o if o.last.parent.nil?; o << o.last.parent } }
    sort = lambda { |list| list.sort_by { |e| chain.call(e).count } }
    sort.call(spans)
  end
  let(:rack_span) { sorted_spans.reverse.find { |x| x.name == Datadog::Contrib::Rack::Ext::SPAN_REQUEST } }
  let(:span) { sorted_spans.reverse.find { |x| x.name == Datadog::Contrib::Sinatra::Ext::SPAN_REQUEST } }
  let(:route_span) { sorted_spans.find { |x| x.name == Datadog::Contrib::Sinatra::Ext::SPAN_ROUTE } }

  let(:app) { sinatra_app }

  before do
    Datadog.configure do |c|
      c.use :sinatra, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:sinatra].reset_configuration!
    example.run
    Datadog.registry[:sinatra].reset_configuration!
  end

  shared_examples 'sinatra examples' do |opts = {}|
    let(:nested_span_count) { defined?(mount_nested_app) && mount_nested_app ? 2 : 0 }

    context 'when configured' do
      context 'with default settings' do
        context 'and a simple request is made' do
          subject(:response) { get url }

          # let(:top_span) { defined?(super) ? super() : rack_span }

          context 'on matching app' do
            before { skip if opts[:matching_app] == false }

            let(:route_parent) { defined?(mount_nested_app) && mount_nested_app ? nested_span : span }

            it do
              is_expected.to be_ok

              expect(span).to be_request_span parent: rack_span, http_tags: true
              expect(route_span).to be_request_span parent: route_parent
              expect(span.resource).to eq('GET /')
              expect(rack_span.resource).to eq('GET /') # either / or 200
            end
          end

          it_behaves_like 'analytics for integration', ignore_global_flag: false do
            before { is_expected.to be_ok }

            let(:analytics_enabled_var) { Datadog::Contrib::Sinatra::Ext::ENV_ANALYTICS_ENABLED }
            let(:analytics_sample_rate_var) { Datadog::Contrib::Sinatra::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          end

          it_behaves_like 'measured span for integration', true do
            before { is_expected.to be_ok }
          end

          context 'which sets X-Request-Id on the response' do
            it do
              subject
              skip('not matching app span') unless span.get_tag(Datadog::Contrib::Sinatra::Ext::TAG_ROUTE_PATH)
              expect(span.get_tag('http.response.headers.x_request_id')).to eq('test id')
            end
          end
        end

        context 'and a request with a query string and fragment is made' do
          subject(:response) { get '/#foo?a=1' }

          it do
            is_expected.to be_ok
            expect(span.resource).to eq('GET /')
            expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/')
          end
        end

        context 'and a request to a wildcard route is made' do
          subject(:response) { get '/wildcard/1/2/3' }

          let(:matching_app?) { span.get_tag(Datadog::Contrib::Sinatra::Ext::TAG_APP_NAME) == top_app_name }

          context 'with matching app' do
            before do
              subject
              skip unless matching_app?
            end

            it do
              is_expected.to be_ok

              expect(span.resource).to eq('GET /wildcard/*')
              expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/wildcard/1/2/3')
              expect(span.get_tag(Datadog::Contrib::Sinatra::Ext::TAG_ROUTE_PATH)).to eq('/wildcard/*')
            end
          end

          context 'with non-matching app' do
            before do
              subject
              skip if matching_app?
            end

            # TODO: replace with suggested solution below (or other alternative)
            it '[TODO:legacy] sets high-cardinality path as resource for non-matching app' do
              is_expected.to be_ok
              expect(span.resource).to eq('GET /wildcard/1/2/3')
            end

            xit '[TODO:BREAKING:suggested] sets resource for non-matching app' do
              is_expected.to be_ok
              expect(span.resource).to eq('GET')
            end
          end
        end

        context 'and a request to a template route is made' do
          subject(:response) { get '/erb' }

          let(:root_span) { request_span.parent }
          let(:request_span) { route_span.parent }
          let(:route_span) { template_parent_span.parent }
          let(:template_parent_span) { template_child_span.parent }
          let(:template_child_span) { sorted_spans.find { |s| s.get_tag('sinatra.template_name') == 'layout' } }

          before do
            expect(response).to be_ok
          end

          describe 'the sinatra.request span' do
            subject(:span) { request_span }

            it do
              expect(span.resource).to eq('GET /erb')
              expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/erb')
            end

            it_behaves_like 'measured span for integration', true
          end

          describe 'the sinatra.render_template child span' do
            subject(:span) { template_parent_span }

            it do
              expect(span.name).to eq(Datadog::Contrib::Sinatra::Ext::SPAN_RENDER_TEMPLATE)
              expect(span.resource).to eq('sinatra.render_template')
              expect(span.get_tag('sinatra.template_name')).to eq('msg')
            end

            it_behaves_like 'measured span for integration', true
          end

          describe 'the sinatra.render_template grandchild span' do
            subject(:span) { template_child_span }

            it do
              expect(span.name).to eq(Datadog::Contrib::Sinatra::Ext::SPAN_RENDER_TEMPLATE)
              expect(span.resource).to eq('sinatra.render_template')
              expect(span.get_tag('sinatra.template_name')).to eq('layout')
            end

            it_behaves_like 'measured span for integration', true
          end
        end

        context 'and a request to a literal template route is made' do
          subject(:response) { get '/erb_literal' }

          let(:template_parent_span) { sorted_spans[-2] }
          let(:template_child_span) { sorted_spans[-1] }

          before do
            expect(response).to be_ok
            expect(spans).to have(5 + nested_span_count).items
          end

          describe 'the sinatra.request span' do
            it do
              expect(span.resource).to eq('GET /erb_literal')
              expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/erb_literal')
              expect(span.parent).to be rack_span
            end

            it_behaves_like 'measured span for integration', true
          end

          describe 'the sinatra.render_template child span' do
            subject(:span) { template_parent_span }

            it do
              expect(span.name).to eq(Datadog::Contrib::Sinatra::Ext::SPAN_RENDER_TEMPLATE)
              expect(span.resource).to eq('sinatra.render_template')
              expect(span.get_tag('sinatra.template_name')).to be nil
              expect(span.parent).to eq(route_span)
            end

            it_behaves_like 'measured span for integration', true
          end

          describe 'the sinatra.render_template grandchild span' do
            subject(:span) { template_child_span }

            it do
              expect(span.name).to eq(Datadog::Contrib::Sinatra::Ext::SPAN_RENDER_TEMPLATE)
              expect(span.resource).to eq('sinatra.render_template')
              expect(span.get_tag('sinatra.template_name')).to eq('layout')
              expect(span.parent).to eq(template_parent_span)
            end

            it_behaves_like 'measured span for integration', true
          end
        end

        context 'and a bad request is made' do
          subject(:response) { get '/client_error' }

          it do
            is_expected.to be_bad_request
            expect(span).to_not have_error
          end
        end

        context 'and a request resulting in an internal error is made' do
          subject(:response) { get '/server_error' }

          it do
            is_expected.to be_server_error
            expect(spans).to have(3 + nested_span_count).items
            expect(span).to_not have_error_type
            expect(span).to_not have_error_message
            expect(span.status).to eq(1)
          end
        end

        context 'and a request that raises an exception is made' do
          subject(:response) { get '/error' }

          it do
            is_expected.to be_server_error
            expect(spans).to have(3 + nested_span_count).items
            expect(span).to have_error_type('RuntimeError')
            expect(span).to have_error_message('test error')
            expect(span.status).to eq(1)
          end
        end

        context 'and a request to a nonexistent route' do
          subject(:response) { get '/not_a_route' }

          it do
            is_expected.to be_not_found
            expect(spans).to have(2 + nested_span_count).items

            expect(span.service).to eq(Datadog::Contrib::Sinatra::Ext::SERVICE_NAME)
            expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
            expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/not_a_route')
            expect(span.get_tag(Datadog::Contrib::Sinatra::Ext::TAG_APP_NAME)).to eq(app_name)
            expect(span.get_tag(Datadog::Contrib::Sinatra::Ext::TAG_ROUTE_PATH)).to eq('/not_a_route')
            expect(span.span_type).to eq(Datadog::Ext::HTTP::TYPE_INBOUND)
            expect(span).to_not have_error

            if nested_span_count > 0
              expect(span.resource).to eq('GET /not_a_route')
              expect(nested_span.resource).to eq('GET /not_a_route')
            else
              expect(span.resource).to eq('GET /not_a_route')
            end

            expect(span.parent).to be(rack_span)
            binding.pry if rack_span.resource == 'GET 404'
            expect(rack_span.resource).to eq('GET /not_a_route')
          end
        end

        describe 'span resource' do
          subject(:response) { get '/span_resource' }

          let(:spans) { observed[:spans] }

          before do
            is_expected.to be_ok
          end

          it 'sets the route span resource before calling the route' do
            expect(observed[:active_span]).to eq(name: 'sinatra.route', resource: 'GET /span_resource')
          end

          it 'sets the sinatra request span resource before calling the route' do
            expect(observed[:sinatra_request_span]).to eq(name: 'sinatra.request', resource: 'GET /span_resource')
          end
        end
      end

      context 'with a custom service name' do
        let(:configuration_options) { super().merge(service_name: service_name) }
        let(:service_name) { 'my-sinatra-app' }

        context 'and a simple request is made' do
          subject(:response) { get '/' }

          it do
            is_expected.to be_ok
            expect(spans).to have(3 + nested_span_count).items
            expect(span.service).to eq(service_name)
          end
        end
      end
    end

    context 'when the tracer is disabled' do
      subject(:response) { get '/' }

      let(:tracer) { get_test_tracer(enabled: false) }

      it do
        is_expected.to be_ok
        expect(spans).to be_empty
      end
    end
  end

  shared_examples 'header tags' do
    context 'and a simple request is made' do
      subject(:response) { get '/', query_string, headers }

      let(:query_string) { {} }
      let(:headers) { {} }

      let(:configuration_options) { super().merge(headers: { request: request_headers, response: response_headers }) }
      let(:request_headers) { [] }
      let(:response_headers) { [] }

      before { is_expected.to be_ok }

      context 'with a header that should be tagged' do
        let(:request_headers) { ['X-Request-Header'] }
        let(:headers) { { 'HTTP_X_REQUEST_HEADER' => header_value } }
        let(:header_value) { SecureRandom.uuid }

        it { expect(span.get_tag('http.request.headers.x_request_header')).to eq(header_value) }
      end

      context 'with a header that should not be tagged' do
        let(:headers) { { 'HTTP_X_REQUEST_HEADER' => header_value } }
        let(:header_value) { SecureRandom.uuid }

        it { expect(span.get_tag('http.request.headers.x_request_header')).to be nil }
      end
    end
  end

  shared_examples 'distributed tracing' do
    context 'default' do
      context 'and a simple request is made' do
        subject(:response) { get '/', query_string, headers }

        let(:query_string) { {} }
        let(:headers) { {} }

        context 'with distributed tracing headers' do
          let(:headers) do
            {
              'HTTP_X_DATADOG_TRACE_ID' => '1',
              'HTTP_X_DATADOG_PARENT_ID' => '2',
              'HTTP_X_DATADOG_SAMPLING_PRIORITY' => Datadog::Ext::Priority::USER_KEEP.to_s,
              'HTTP_X_DATADOG_ORIGIN' => 'synthetics'
            }
          end

          it do
            is_expected.to be_ok
            expect(span.trace_id).to eq(1)
            expect(span.parent).to eq(rack_span)
            expect(rack_span.trace_id).to eq(1)
            expect(rack_span.parent_id).to eq(2)
            expect(rack_span.get_metric(Datadog::Ext::DistributedTracing::SAMPLING_PRIORITY_KEY)).to eq(2.0)
            expect(rack_span.get_tag(Datadog::Ext::DistributedTracing::ORIGIN_KEY)).to eq('synthetics')
          end
        end
      end
    end

    context 'disabled' do
      let(:configuration_options) { super().merge(distributed_tracing: false) }

      context 'and a simple request is made' do
        subject(:response) { get '/', query_string, headers }

        let(:query_string) { {} }
        let(:headers) { {} }

        context 'without distributed tracing headers' do
          let(:headers) do
            {
              'HTTP_X_DATADOG_TRACE_ID' => '1',
              'HTTP_X_DATADOG_PARENT_ID' => '2',
              'HTTP_X_DATADOG_SAMPLING_PRIORITY' => Datadog::Ext::Priority::USER_KEEP.to_s
            }
          end

          it do
            is_expected.to be_ok
            expect(span.trace_id).to_not eq(1)
            expect(span.parent_id).to_not eq(2)
            expect(span.get_metric(Datadog::Ext::DistributedTracing::SAMPLING_PRIORITY_KEY)).to_not eq(2.0)
          end
        end
      end
    end
  end

  context 'with classic app' do
    let(:sinatra_app) do
      sinatra_routes = self.sinatra_routes
      Class.new(Sinatra::Application) do
        instance_exec(&sinatra_routes)
      end
    end

    let(:app_name) { 'Sinatra::Application' }
    let(:top_app_name) { app_name }

    include_examples 'sinatra examples'
  end

  context 'with modular app' do
    let(:sinatra_app) do
      mount_nested_app = self.mount_nested_app
      stub_const('NestedApp', Class.new(Sinatra::Base) do
        register Datadog::Contrib::Sinatra::Tracer

        get '/nested' do
          headers['X-Request-ID'] = 'test id'
          'nested ok'
        end
      end)

      sinatra_routes = self.sinatra_routes
      stub_const('App', Class.new(Sinatra::Base) do
        register Datadog::Contrib::Sinatra::Tracer
        use NestedApp if mount_nested_app

        instance_exec(&sinatra_routes)
      end)
    end

    let(:app_name) { top_app_name }
    let(:top_app_name) { 'App' }
    let(:mount_nested_app) { false }

    include_examples 'sinatra examples'

    context 'with nested app' do
      let(:mount_nested_app) { true }
      let(:top_span) { spans.find { |x| x.get_tag(Datadog::Contrib::Sinatra::Ext::TAG_APP_NAME) == top_app_name } }
      let(:top_rack_span) { spans.find { |x| x.name == Datadog::Contrib::Rack::Ext::SPAN_REQUEST && x == top_span.parent  } }
      let(:nested_span) { spans.find { |x| x.get_tag(Datadog::Contrib::Sinatra::Ext::TAG_APP_NAME) == nested_app_name } }
      let(:nested_rack_span) { spans.find { |x| x.name == Datadog::Contrib::Rack::Ext::SPAN_REQUEST && x == nested_span.parent  } }
      let(:nested_app_name) { 'NestedApp' }

      context 'making request to top level app' do
        let(:span) { top_span }
        let(:rack_span) { top_rack_span }

        include_examples 'sinatra examples'
        include_examples 'header tags'
        include_examples 'distributed tracing'
      end

      context 'making request to nested app' do
        let(:app_name) { nested_app_name }
        let(:url) { '/nested' }

        context 'asserting the parent span' do
          let(:app_name) { top_app_name }
          let(:span) { top_span }
          let(:rack_span) { top_rack_span }

          include_examples 'sinatra examples', matching_app: false
          include_examples 'header tags'
          include_examples 'distributed tracing'
        end

        context 'matching the nested span' do
          let(:span) { nested_span }
          let(:rack_span) { nested_rack_span }

          it 'creates spans for intermediate Sinatra apps' do
            is_expected.to be_ok
            expect(spans).to have(5).items

            expect(top_span).to be_request_span resource: 'GET', app_name: top_app_name, matching_app: false, parent: top_rack_span
            expect(top_rack_span).not_to be_nil
            expect(top_rack_span.parent).to be_nil
            expect(top_rack_span.resource).to eq('GET')
            expect(span).to be_request_span parent: nested_rack_span
            expect(nested_rack_span).not_to be_nil
            expect(nested_rack_span.parent).to eq(top_span)
            expect(route_span).to be_route_span parent: span
            expect(nested_rack_span.resource).to eq(resource)
          end

          context 'with distributed_tracing' do
            subject(:response) { get '/', query_string, headers }

            let(:query_string) { {} }
            let(:headers) do
              {
                'HTTP_X_DATADOG_TRACE_ID' => '1',
                'HTTP_X_DATADOG_PARENT_ID' => '2',
                'HTTP_X_DATADOG_SAMPLING_PRIORITY' => Datadog::Ext::Priority::USER_KEEP.to_s,
                'HTTP_X_DATADOG_ORIGIN' => 'synthetics'
              }
            end

            it do
              is_expected.to be_ok
              expect(span.trace_id).to eq(1)
              expect(span.parent_id).to_not eq(2)
              expect(span.get_metric(Datadog::Ext::DistributedTracing::SAMPLING_PRIORITY_KEY)).to_not eq(2.0)
              expect(rack_span.trace_id).to eq(1)
              expect(rack_span.parent_id).to_not eq(2) # TODO: fails despite being nested
              expect(rack_span.get_metric(Datadog::Ext::DistributedTracing::SAMPLING_PRIORITY_KEY)).to_not eq(2.0)
            end
          end

          context 'with route not found' do
            let(:url) { '/not_a_route' }

            # TODO: `resource` should not be high-cardinality for not found routes
            # TODO: Using the HTTP method is one suggested alternative, as we
            # TODO: don't yet have the HTTP response available to also retrieve the
            # TODO: status code at middleware processing time.
            # let(:resource) { 'GET' }

            it do
              is_expected.to be_not_found
              expect(spans).to have(4).items

              expect(top_span).to be_request_span app_name: top_app_name, resource: 'GET /not_a_route', parent: top_rack_span
              expect(span).to be_request_span parent: nested_rack_span
            end
          end
        end
      end
    end

    context 'when modular app does not register the Datadog::Contrib::Sinatra::Tracer middleware' do
      let(:sinatra_app) do
        sinatra_routes = self.sinatra_routes
        stub_const('App', Class.new(Sinatra::Base) do
          instance_exec(&sinatra_routes)
        end)
      end

      subject(:response) { get url }

      before do
        allow(Datadog.logger).to receive(:warn)
        Datadog::Contrib::Sinatra::Tracer::Base
          .const_get('MISSING_REQUEST_SPAN_ONLY_ONCE').send(:reset_ran_once_state_for_tests)
      end

      it { is_expected.to be_ok }

      it 'logs a warning' do
        expect(Datadog.logger).to receive(:warn) do |&message|
          expect(message.call).to include 'Sinatra integration is misconfigured'
        end

        # NOTE: We actually need to check that the request finished ok, as sinatra may otherwise "swallow" an RSpec
        # exception and thus the test will appear to pass because the RSpec exception doesn't propagate out
        is_expected.to be_ok
      end
    end
  end

  RSpec::Matchers.define :be_request_span do |opts = {}|
    match(notify_expectation_failures: true) do |span|
      app_name = opts[:app_name] || self.app_name
      expect(span.service).to eq(Datadog::Contrib::Sinatra::Ext::SERVICE_NAME)
      expect(span.resource).to eq(opts[:resource] || resource)
      expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq(http_method) if opts[:http_tags]
      expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq(url) if opts[:http_tags]
      expect(span.get_tag('http.response.headers.content_type')).to eq('text/html;charset=utf-8') if opts[:http_tags]
      expect(span.get_tag(Datadog::Contrib::Sinatra::Ext::TAG_APP_NAME)).to eq(app_name)
      expect(span.get_tag(Datadog::Contrib::Sinatra::Ext::TAG_ROUTE_PATH)).to eq(url) if app_name == self.app_name
      expect(span.get_tag(Datadog::Contrib::Sinatra::Ext::TAG_SCRIPT_NAME)).to be_nil
      expect(span.span_type).to eq(Datadog::Ext::HTTP::TYPE_INBOUND)
      expect(span).to_not have_error
      expect(span.parent).to be(opts[:parent])
    end
  end

  RSpec::Matchers.define :be_route_span do |opts = {}|
    match(notify_expectation_failures: true) do |span|
      expect(span.service).to eq(Datadog::Contrib::Sinatra::Ext::SERVICE_NAME)
      expect(span.resource).to eq(resource)
      expect(span.get_tag(Datadog::Contrib::Sinatra::Ext::TAG_APP_NAME)).to eq(app_name)
      expect(span.get_tag(Datadog::Contrib::Sinatra::Ext::TAG_ROUTE_PATH)).to eq(url)
      expect(span.span_type).to eq(Datadog::Ext::HTTP::TYPE_INBOUND)
      expect(span).to_not have_error
      expect(span.parent).to be(opts[:parent]) if opts[:parent]
    end
  end
end
