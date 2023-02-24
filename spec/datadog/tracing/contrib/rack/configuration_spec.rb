require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'
require 'rack/test'

require 'rack'
require 'ddtrace'
require 'datadog/tracing/contrib/rack/middlewares'

RSpec.describe 'Rack integration configuration' do
  include Rack::Test::Methods

  let(:configuration_options) { {} }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :rack, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:rack].reset_configuration!
    example.run
    Datadog.registry[:rack].reset_configuration!
  end

  shared_context 'an incoming HTTP request' do
    subject(:response) { get '/' }

    let(:app) do
      Rack::Builder.new do
        use Datadog::Tracing::Contrib::Rack::TraceMiddleware

        map '/' do
          run(proc { |_env| [200, { 'Content-Type' => 'text/html' }, ['OK']] })
        end
      end.to_app
    end
  end

  it_behaves_like 'analytics for integration', ignore_global_flag: false do
    include_context 'an incoming HTTP request'
    before { is_expected.to be_ok }

    let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Rack::Ext::ENV_ANALYTICS_ENABLED }
    let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Rack::Ext::ENV_ANALYTICS_SAMPLE_RATE }
  end

  it_behaves_like 'measured span for integration', true do
    include_context 'an incoming HTTP request'
    before { is_expected.to be_ok }
  end

  describe 'request queueing' do
    shared_context 'queue header' do
      let(:queue_value) { "t=#{queue_time}" }
      let(:queue_time) { (Time.now.utc - 5).to_i }

      before do
        header queue_header, queue_value
      end
    end

    shared_context 'no queue header' do
      let(:queue_header) { nil }
      let(:queue_value) { nil }
    end

    shared_examples_for 'a Rack request with queuing including the request' do
      let(:configuration_options) { super().merge(request_queuing: :include_request) }

      it 'produces a queued Rack trace' do
        is_expected.to be_ok

        expect(trace.resource).to eq('GET 200')

        expect(spans).to have(2).items

        server_queue_span = spans[0]
        rack_span = spans[1]

        web_service_name = Datadog.configuration.tracing[:rack][:web_service_name]

        expect(server_queue_span.name).to eq('http_server.queue')
        expect(server_queue_span.span_type).to eq('proxy')
        expect(server_queue_span.service).to eq(web_service_name)
        expect(server_queue_span.start_time.to_i).to eq(queue_time)
        expect(server_queue_span.get_tag(Datadog::Core::Runtime::Ext::TAG_LANG)).to be_nil
        expect(server_queue_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(web_service_name)
        expect(server_queue_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('rack')
        expect(server_queue_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('queue')

        expect(rack_span.name).to eq('rack.request')
        expect(rack_span.span_type).to eq('web')
        expect(rack_span.service).to eq(Datadog.configuration.service)
        expect(rack_span.resource).to eq('GET 200')
        expect(rack_span.get_tag('http.method')).to eq('GET')
        expect(rack_span.get_tag('http.status_code')).to eq('200')
        expect(rack_span.get_tag('http.url')).to eq('/')
        expect(rack_span.status).to eq(0)
        expect(rack_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('rack')
        expect(rack_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('request')
        expect(rack_span.parent_id).to eq(server_queue_span.span_id)
      end
    end

    shared_examples_for 'a Rack request with queuing excluding the request' do
      let(:configuration_options) { super().merge(request_queuing: :exclude_request) }

      it 'produces a queued Rack trace' do
        is_expected.to be_ok

        expect(trace.resource).to eq('GET 200')

        expect(spans).to have(3).items

        server_request_span = spans[1]
        server_queue_span = spans[0]
        rack_span = spans[2]

        web_service_name = Datadog.configuration.tracing[:rack][:web_service_name]

        expect(server_request_span.name).to eq('http.proxy.request')
        expect(server_request_span.span_type).to eq('proxy')
        expect(server_request_span.service).to eq(web_service_name)
        expect(server_request_span.start_time.to_i).to eq(queue_time)
        expect(server_request_span.get_tag(Datadog::Core::Runtime::Ext::TAG_LANG)).to be_nil
        expect(server_request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(web_service_name)
        expect(server_request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('http_proxy')
        expect(server_request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('request')

        expect(server_queue_span.name).to eq('http.proxy.queue')
        expect(server_queue_span.span_type).to eq('proxy')
        expect(server_queue_span.service).to eq(web_service_name)
        expect(server_queue_span.start_time.to_i).to eq(queue_time)
        expect(server_queue_span.get_tag(Datadog::Core::Runtime::Ext::TAG_LANG)).to be_nil
        expect(server_queue_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(web_service_name)
        expect(server_queue_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('http_proxy')
        expect(server_queue_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('queue')
        expect(server_queue_span.parent_id).to eq(server_request_span.span_id)

        expect(rack_span.name).to eq('rack.request')
        expect(rack_span.span_type).to eq('web')
        expect(rack_span.service).to eq(Datadog.configuration.service)
        expect(rack_span.resource).to eq('GET 200')
        expect(rack_span.get_tag('http.method')).to eq('GET')
        expect(rack_span.get_tag('http.status_code')).to eq('200')
        expect(rack_span.get_tag('http.url')).to eq('/')
        expect(rack_span.status).to eq(0)
        expect(rack_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('rack')
        expect(rack_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('request')
        expect(rack_span.parent_id).to eq(server_request_span.span_id)
      end
    end

    shared_examples_for 'a Rack request without queuing' do
      it 'produces a non-queued Rack trace' do
        is_expected.to be_ok

        expect(trace.resource).to eq('GET 200')

        expect(spans).to have(1).items

        expect(span).to_not be nil
        expect(span.name).to eq('rack.request')
        expect(span.span_type).to eq('web')
        expect(span.service).to eq(Datadog.configuration.service)
        expect(span.resource).to eq('GET 200')
        expect(span.get_tag('http.method')).to eq('GET')
        expect(span.get_tag('http.status_code')).to eq('200')
        expect(span.get_tag('http.url')).to eq('/')
        expect(span.status).to eq(0)
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
          .to eq('rack')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq('request')

        expect(span.parent_id).to eq(0)
      end
    end

    context 'when enabled' do
      let(:configuration_options) { super().merge(request_queuing: :exclude_request) }

      context 'and a request is received' do
        include_context 'an incoming HTTP request'

        context 'with X-Request-Start header' do
          include_context 'queue header' do
            let(:queue_header) { 'X-Request-Start' }
          end

          it_behaves_like 'a Rack request with queuing including the request'
          it_behaves_like 'a Rack request with queuing excluding the request'

          context 'given a custom web service name' do
            let(:configuration_options) { super().merge(web_service_name: web_service_name) }
            let(:web_service_name) { 'nginx' }

            it_behaves_like 'a Rack request with queuing including the request' do
              it 'sets the custom service name' do
                is_expected.to be_ok

                queue_span = spans.find { |s| s.name == Datadog::Tracing::Contrib::Rack::Ext::SPAN_HTTP_SERVER_QUEUE }

                expect(queue_span.service).to eq(web_service_name)
              end
            end

            it_behaves_like 'a Rack request with queuing excluding the request' do
              it 'sets the custom service name' do
                is_expected.to be_ok

                queue_span = spans.find { |s| s.name == Datadog::Tracing::Contrib::Rack::Ext::SPAN_HTTP_PROXY_QUEUE }

                expect(queue_span.service).to eq(web_service_name)
              end
            end
          end
        end

        context 'with X-Queue-Start header' do
          include_context 'queue header' do
            let(:queue_header) { 'X-Queue-Start' }
          end

          it_behaves_like 'a Rack request with queuing including the request'
          it_behaves_like 'a Rack request with queuing excluding the request'
        end

        # Ensure a queuing Span is NOT created if there is a clock skew
        # where the starting time is greater than current host Time.now
        context 'with a skewed queue header' do
          before { header 'X-Request-Start', (Time.now.utc + 5).to_i }

          it_behaves_like 'a Rack request without queuing'
        end

        # Ensure a queuing Span is NOT created if the header is wrong
        context 'with a invalid queue header' do
          before { header 'X-Request-Start', 'foobar' }

          it_behaves_like 'a Rack request without queuing'
        end

        context 'without queue header' do
          include_context 'no queue header'
          it_behaves_like 'a Rack request without queuing'
        end
      end
    end

    context 'when disabled' do
      let(:configuration_options) { super().merge(request_queuing: false) }

      context 'and a request is received' do
        include_context 'an incoming HTTP request'

        context 'with X-Request-Start header' do
          include_context 'queue header' do
            let(:queue_header) { 'X-Request-Start' }
          end

          it_behaves_like 'a Rack request without queuing'
        end

        context 'with X-Queue-Start header' do
          include_context 'queue header' do
            let(:queue_header) { 'X-Queue-Start' }
          end

          it_behaves_like 'a Rack request without queuing'
        end

        context 'without queue header' do
          include_context 'no queue header'
          it_behaves_like 'a Rack request without queuing'
        end
      end
    end
  end
end
