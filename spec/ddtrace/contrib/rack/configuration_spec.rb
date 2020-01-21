require 'spec_helper'
require 'ddtrace/contrib/analytics_examples'
require 'rack/test'

require 'rack'
require 'ddtrace'
require 'ddtrace/contrib/rack/middlewares'

RSpec.describe 'Rack integration configuration' do
  include Rack::Test::Methods

  let(:tracer) { get_test_tracer }
  let(:configuration_options) { { tracer: tracer } }

  let(:spans) { tracer.writer.spans }
  let(:span) { spans.first }

  before(:each) do
    Datadog.configure do |c|
      c.use :rack, configuration_options
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
        use Datadog::Contrib::Rack::TraceMiddleware

        map '/' do
          run(proc { |_env| [200, { 'Content-Type' => 'text/html' }, 'OK'] })
        end
      end.to_app
    end
  end

  it_behaves_like 'analytics for integration', ignore_global_flag: false do
    include_context 'an incoming HTTP request'
    before { is_expected.to be_ok }
    let(:analytics_enabled_var) { Datadog::Contrib::Rack::Ext::ENV_ANALYTICS_ENABLED }
    let(:analytics_sample_rate_var) { Datadog::Contrib::Rack::Ext::ENV_ANALYTICS_SAMPLE_RATE }
  end

  describe 'request queueing' do
    shared_context 'queue header' do
      let(:queue_value) { "t=#{queue_time}" }
      let(:queue_time) { (Time.now.utc - 5).to_i }

      before(:each) do
        header queue_header, queue_value
      end
    end

    shared_context 'no queue header' do
      let(:queue_header) { nil }
      let(:queue_value) { nil }
    end

    shared_examples_for 'a Rack request with queuing' do
      let(:queue_span) { spans.first }
      let(:rack_span) { spans.last }

      it 'produces a queued Rack trace' do
        is_expected.to be_ok
        expect(spans).to have(2).items

        expect(queue_span.name).to eq('http_server.queue')
        expect(queue_span.span_type).to eq('proxy')
        expect(queue_span.service).to eq(Datadog.configuration[:rack][:web_service_name])
        expect(queue_span.start_time.to_i).to eq(queue_time)
        # Queue span gets tagged for runtime metrics because its a local root span.
        # TODO: It probably shouldn't get tagged like this in the future; it's not part of the runtime.

        expect(rack_span.name).to eq('rack.request')
        expect(rack_span.span_type).to eq('web')
        expect(rack_span.service).to eq(Datadog.configuration[:rack][:service_name])
        expect(rack_span.resource).to eq('GET 200')
        expect(rack_span.get_tag('http.method')).to eq('GET')
        expect(rack_span.get_tag('http.status_code')).to eq('200')
        expect(rack_span.get_tag('http.url')).to eq('/')
        expect(rack_span.status).to eq(0)

        expect(queue_span.span_id).to eq(rack_span.parent_id)
      end
    end

    shared_examples_for 'a Rack request without queuing' do
      it 'produces a non-queued Rack trace' do
        is_expected.to be_ok
        expect(spans).to have(1).items

        expect(span).to_not be nil
        expect(span.name).to eq('rack.request')
        expect(span.span_type).to eq('web')
        expect(span.service).to eq(Datadog.configuration[:rack][:service_name])
        expect(span.resource).to eq('GET 200')
        expect(span.get_tag('http.method')).to eq('GET')
        expect(span.get_tag('http.status_code')).to eq('200')
        expect(span.get_tag('http.url')).to eq('/')
        expect(span.status).to eq(0)

        expect(span.parent_id).to eq(0)
      end
    end

    context 'when enabled' do
      let(:configuration_options) { super().merge(request_queuing: true) }

      context 'and a request is received' do
        include_context 'an incoming HTTP request'

        context 'with X-Request-Start header' do
          include_context 'queue header' do
            let(:queue_header) { 'X-Request-Start' }
          end

          it_behaves_like 'a Rack request with queuing'

          context 'given a custom web service name' do
            let(:configuration_options) { super().merge(web_service_name: web_service_name) }
            let(:web_service_name) { 'nginx' }

            it_behaves_like 'a Rack request with queuing' do
              it 'sets the custom service name' do
                is_expected.to be_ok
                expect(queue_span.service).to eq(web_service_name)
              end
            end
          end
        end

        context 'with X-Queue-Start header' do
          include_context 'queue header' do
            let(:queue_header) { 'X-Queue-Start' }
          end

          it_behaves_like 'a Rack request with queuing'
        end

        # Ensure a queuing Span is NOT created if there is a clock skew
        # where the starting time is greater than current host Time.now
        context 'with a skewed queue header' do
          before(:each) { header 'X-Request-Start', (Time.now.utc + 5).to_i }
          it_behaves_like 'a Rack request without queuing'
        end

        # Ensure a queuing Span is NOT created if the header is wrong
        context 'with a invalid queue header' do
          before(:each) { header 'X-Request-Start', 'foobar' }
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
