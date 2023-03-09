require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'
require 'ddtrace'
require 'datadog/tracing/contrib/grape/patcher'
require 'datadog/tracing/contrib/rack/middlewares'
require 'rack/test'
require 'grape'

RSpec.describe 'Grape instrumentation' do
  include Rack::Test::Methods

  let(:configuration_options) { {} }

  let(:render_span) { spans.find { |x| x.name == Datadog::Tracing::Contrib::Grape::Ext::SPAN_ENDPOINT_RENDER } }
  let(:run_span) { spans.find { |x| x.name == Datadog::Tracing::Contrib::Grape::Ext::SPAN_ENDPOINT_RUN } }
  let(:run_filter_span) { spans.find { |x| x.name == Datadog::Tracing::Contrib::Grape::Ext::SPAN_ENDPOINT_RUN_FILTERS } }
  let(:span) { spans.last }

  let(:testing_api) do
    # patch Grape before the application
    Datadog::Tracing::Contrib::Grape::Patcher.patch

    stub_const(
      'TestingAPI',
      Class.new(Grape::API) do
        namespace :base do
          desc 'Returns a success message'
          get :success do
            'OK'
          end

          desc 'Returns an error'
          get :hard_failure do
            raise StandardError, 'Ouch!'
          end
        end

        namespace :filtered do
          before do
            sleep(0.01)
          end

          after do
            sleep(0.01)
          end

          desc 'Returns a success message before and after filter processing'
          get :before_after do
            'OK'
          end
        end

        namespace :filtered_exception do
          before do
            raise StandardError, 'Ouch!'
          end

          desc 'Returns an error in the filter'
          get :before do
            'OK'
          end
        end

        resource :widgets do
          desc 'Returns a list of widgets'
          get do
            '[]'
          end

          desc 'creates a widget'
          post do
            '{}'
          end
        end

        namespace :nested do
          resource :widgets do
            desc 'Returns a list of widgets'
            get do
              '[]'
            end
          end
        end

        resource :span_resource do
          get :span_resource do
            'OK'
          end
        end
      end
    )
  end

  let(:rack_testing_api) do
    # patch Grape before the application
    Datadog::Tracing::Contrib::Grape::Patcher.patch

    stub_const(
      'RackTestingAPI',
      Class.new(Grape::API) do
        desc 'Returns a success message'
        get :success do
          'OK'
        end

        desc 'Returns an error'
        get :hard_failure do
          raise StandardError, 'Ouch!'
        end

        resource :span_resource_rack do
          get :span_resource do
            'OK'
          end
        end
      end
    )

    # create a custom Rack application with the Rack middleware and a Grape API
    Rack::Builder.new do
      use Datadog::Tracing::Contrib::Rack::TraceMiddleware
      map '/api/' do
        run RackTestingAPI
      end
    end.to_app
  end

  before do
    Datadog.configure do |c|
      c.tracing.instrument :rack, configuration_options if with_rack
      c.tracing.instrument :grape, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:rack].reset_configuration!
    Datadog.registry[:grape].reset_configuration!
    example.run
    Datadog.registry[:rack].reset_configuration!
    Datadog.registry[:grape].reset_configuration!
  end

  context 'without rack' do
    let(:app) { testing_api }

    let(:with_rack) { false }

    context 'success' do
      context 'without filters' do
        subject(:response) { get '/base/success' }

        it_behaves_like 'measured span for integration', true do
          before { is_expected.to be_ok }
        end

        it_behaves_like 'analytics for integration', ignore_global_flag: false do
          let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Grape::Ext::ENV_ANALYTICS_ENABLED }
          let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Grape::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          before { is_expected.to be_ok }
        end

        it 'traces the endpoint body' do
          is_expected.to be_ok
          expect(response.body).to eq('OK')
          expect(spans.length).to eq(2)

          expect(render_span.name).to eq('grape.endpoint_render')
          expect(render_span.span_type).to eq('template')
          expect(render_span.service).to eq(tracer.default_service)
          expect(render_span.resource).to eq('grape.endpoint_render')
          expect(render_span).to_not have_error
          expect(render_span.parent_id).to eq(run_span.span_id)
          expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('grape')
          expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq('endpoint_render')

          expect(run_span.name).to eq('grape.endpoint_run')
          expect(run_span.span_type).to eq('web')
          expect(run_span.service).to eq(tracer.default_service)
          expect(run_span.resource).to eq('TestingAPI GET /base/success')
          expect(run_span).to_not have_error
          expect(run_span).to be_root_span
          expect(run_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('grape')
          expect(run_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq('endpoint_run')
        end
      end

      context 'with filters' do
        subject(:response) { get '/filtered/before_after' }

        it_behaves_like 'measured span for integration', true do
          before { is_expected.to be_ok }
        end

        it_behaves_like 'analytics for integration', ignore_global_flag: false do
          before { is_expected.to be_ok }

          let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Grape::Ext::ENV_ANALYTICS_ENABLED }
          let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Grape::Ext::ENV_ANALYTICS_SAMPLE_RATE }
        end

        it 'traces the endpoint body and all before/after filters' do
          is_expected.to be_ok
          expect(response.body).to eq('OK')
          expect(spans.length).to eq(4)

          render_span, run_span, before_span, after_span = spans

          expect(before_span.name).to eq('grape.endpoint_run_filters')
          expect(before_span.span_type).to eq('web')
          expect(before_span.service).to eq(tracer.default_service)
          expect(before_span.resource).to eq('grape.endpoint_run_filters')
          expect(before_span).to_not have_error
          expect(before_span.parent_id).to eq(run_span.span_id)
          expect(before_span.to_hash[:duration] > 0.01).to be true
          expect(before_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('grape')
          expect(before_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq('endpoint_run_filters')

          expect(render_span.name).to eq('grape.endpoint_render')
          expect(render_span.span_type).to eq('template')
          expect(render_span.service).to eq(tracer.default_service)
          expect(render_span.resource).to eq('grape.endpoint_render')
          expect(render_span).to_not have_error
          expect(render_span.parent_id).to eq(run_span.span_id)
          expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('grape')
          expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq('endpoint_render')

          expect(after_span.name).to eq('grape.endpoint_run_filters')
          expect(after_span.span_type).to eq('web')
          expect(after_span.service).to eq(tracer.default_service)
          expect(after_span.resource).to eq('grape.endpoint_run_filters')
          expect(after_span).to_not have_error
          expect(after_span.parent_id).to eq(run_span.span_id)
          expect(after_span.to_hash[:duration] > 0.01).to be true
          expect(after_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('grape')
          expect(after_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq('endpoint_run_filters')

          expect(run_span.name).to eq('grape.endpoint_run')
          expect(run_span.span_type).to eq('web')
          expect(run_span.service).to eq(tracer.default_service)
          expect(run_span.resource).to eq('TestingAPI GET /filtered/before_after')
          expect(run_span.status).to eq(0)
          expect(run_span).to be_root_span
          expect(run_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('grape')
          expect(run_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq('endpoint_run')
        end
      end
    end

    context 'failure' do
      context 'without filters' do
        subject(:response) { post '/base/hard_failure' }

        it 'handles exceptions' do
          expect(response.body).to eq('405 Not Allowed')
          expect(spans.length).to eq(1)
          expect(spans[0].name).to eq('grape.endpoint_run')
          expect(spans[0].status).to eq(1)
          expect(spans[0].get_tag('error.stack')).to_not be_nil
          expect(spans[0].get_tag('error.type')).to_not be_nil
          expect(spans[0].get_tag('error.message')).to_not be_nil,
            "DEV: 🚧 Flaky test! Please send the maintainers a link for this CI failure. Thank you! 🚧\n" \
            "response=#{response.inspect}\n" \
            "spans=#{spans.inspect}\n"
          expect(spans[0].get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('grape')
          expect(spans[0].get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq('endpoint_run')
        end

        context 'and error_responses' do
          subject(:response) { post '/base/hard_failure' }

          let(:configuration_options) { { error_statuses: '300-399,,xxx-xxx,1111,400-499' } }

          it 'handles exceptions' do
            expect(response.body).to eq('405 Not Allowed')
            expect(spans.length).to eq(1)
            expect(spans[0].name).to eq('grape.endpoint_run')
            expect(spans[0].status).to eq(1)
            expect(spans[0].get_tag('error.stack')).to_not be_nil
            expect(spans[0].get_tag('error.type')).to_not be_nil
            expect(spans[0].get_tag('error.message')).to_not be_nil
            expect(spans[0].get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('grape')
            expect(spans[0].get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
              .to eq('endpoint_run')
          end
        end

        context 'and error_responses with arrays' do
          subject(:response) { post '/base/hard_failure' }

          let(:configuration_options) { { error_statuses: ['300-399', 'xxx-xxx', 1111, 405] } }

          it 'handles exceptions' do
            expect(response.body).to eq('405 Not Allowed')
            expect(spans.length).to eq(1)
            expect(spans[0].name).to eq('grape.endpoint_run')
            expect(spans[0].status).to eq(1)
            expect(spans[0].get_tag('error.stack')).to_not be_nil
            expect(spans[0].get_tag('error.type')).to_not be_nil
            expect(spans[0].get_tag('error.message')).to_not be_nil
            expect(spans[0].get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('grape')
            expect(spans[0].get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
              .to eq('endpoint_run')
          end
        end

        context 'and error_responses with arrays that dont contain exception status' do
          subject(:response) { post '/base/hard_failure' }

          let(:configuration_options) { { error_statuses: ['300-399', 'xxx-xxx', 1111, 406] } }

          it 'handles exceptions' do
            expect(response.body).to eq('405 Not Allowed')
            expect(spans.length).to eq(1)
            expect(spans[0].name).to eq('grape.endpoint_run')
            expect(spans[0]).to_not have_error
            expect(spans[0].get_tag('error.stack')).to be_nil
            expect(spans[0].get_tag('error.type')).to be_nil
            expect(spans[0].get_tag('error.message')).to be_nil
            expect(spans[0].get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('grape')
            expect(spans[0].get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
              .to eq('endpoint_run')
          end
        end

        context 'defaults to >=500 when provided invalid config' do
          subject(:response) { post '/base/hard_failure' }

          let(:configuration_options) { { error_statuses: 'xxx-499' } }

          it 'handles exceptions' do
            expect(response.body).to eq('405 Not Allowed')
            expect(spans.length).to eq(1)
            expect(spans[0].name).to eq('grape.endpoint_run')
            expect(spans[0].status).to eq(0)
            expect(spans[0].get_tag('error.stack')).to be_nil
            expect(spans[0].get_tag('error.type')).to be_nil
            expect(spans[0].get_tag('error.message')).to be_nil
            expect(spans[0].get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('grape')
            expect(spans[0].get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
              .to eq('endpoint_run')
          end
        end
      end

      context 'without filters' do
        subject(:response) { get '/base/hard_failure' }

        it_behaves_like 'measured span for integration', true do
          before do
            expect { subject }.to raise_error(StandardError, 'Ouch!')
          end
        end

        it_behaves_like 'analytics for integration', ignore_global_flag: false do
          let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Grape::Ext::ENV_ANALYTICS_ENABLED }
          let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Grape::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          before do
            expect { subject }.to raise_error(StandardError, 'Ouch!')
          end
        end

        it 'handles exceptions' do
          expect { subject }.to raise_error(StandardError, 'Ouch!')

          expect(spans.length).to eq(2)

          expect(render_span.name).to eq('grape.endpoint_render')
          expect(render_span.span_type).to eq('template')
          expect(render_span.service).to eq(tracer.default_service)
          expect(render_span.resource).to eq('grape.endpoint_render')
          expect(render_span).to have_error

          expect(render_span).to have_error_type('StandardError')
          expect(render_span).to have_error_message('Ouch!')
          expect(render_span.get_tag('error.stack')).to include('grape/tracer_spec.rb')
          expect(render_span.parent_id).to eq(run_span.span_id)

          expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('grape')
          expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq('endpoint_render')

          expect(run_span.name).to eq('grape.endpoint_run')
          expect(run_span.span_type).to eq('web')
          expect(run_span.service).to eq(tracer.default_service)
          expect(run_span.resource).to eq('TestingAPI GET /base/hard_failure')
          expect(run_span).to have_error

          expect(run_span).to have_error_type('StandardError')
          expect(run_span).to have_error_message('Ouch!')
          expect(run_span.get_tag('error.stack')).to include('grape/tracer_spec.rb')
          expect(run_span).to be_root_span

          expect(run_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('grape')
          expect(run_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq('endpoint_run')
        end
      end

      context 'with filters' do
        subject(:response) { get '/filtered_exception/before' }

        it_behaves_like 'measured span for integration', true do
          before do
            expect { subject }.to raise_error(StandardError, 'Ouch!')
          end
        end

        it_behaves_like 'analytics for integration', ignore_global_flag: false do
          let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Grape::Ext::ENV_ANALYTICS_ENABLED }
          let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Grape::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          before do
            expect { subject }.to raise_error(StandardError, 'Ouch!')
          end
        end

        it 'traces the endpoint even if a filter raises an exception' do
          expect { subject }.to raise_error(StandardError, 'Ouch!')

          expect(spans.length).to eq(2)

          run_span, before_span = spans

          expect(before_span.name).to eq('grape.endpoint_run_filters')
          expect(before_span.span_type).to eq('web')
          expect(before_span.service).to eq(tracer.default_service)
          expect(before_span.resource).to eq('grape.endpoint_run_filters')
          expect(before_span).to have_error
          expect(before_span).to have_error_type('StandardError')
          expect(before_span).to have_error_message('Ouch!')
          expect(before_span.get_tag('error.stack')).to include('grape/tracer_spec.rb')
          expect(before_span.parent_id).to eq(run_span.span_id)
          expect(before_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('grape')
          expect(before_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq('endpoint_run_filters')

          expect(run_span.name).to eq('grape.endpoint_run')
          expect(run_span.span_type).to eq('web')
          expect(run_span.service).to eq(tracer.default_service)
          expect(run_span.resource).to eq('TestingAPI GET /filtered_exception/before')
          expect(run_span).to have_error
          expect(run_span).to be_root_span
          expect(run_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('grape')
          expect(run_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq('endpoint_run')
        end
      end
    end

    context 'shared paths' do
      context 'get method' do
        subject(:response) { get '/widgets' }

        it_behaves_like 'measured span for integration', true do
          before { is_expected.to be_ok }
        end

        it_behaves_like 'analytics for integration', ignore_global_flag: false do
          let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Grape::Ext::ENV_ANALYTICS_ENABLED }
          let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Grape::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          before { is_expected.to be_ok }
        end

        it 'traces the endpoint body' do
          is_expected.to be_ok
          expect(response.body).to eq('[]')
          expect(spans.length).to eq(2)

          expect(render_span.name).to eq('grape.endpoint_render')
          expect(render_span.span_type).to eq('template')
          expect(render_span.service).to eq(tracer.default_service)
          expect(render_span.resource).to eq('grape.endpoint_render')
          expect(render_span).to_not have_error
          expect(render_span.parent_id).to eq(run_span.span_id)
          expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('grape')
          expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq('endpoint_render')

          expect(run_span.name).to eq('grape.endpoint_run')
          expect(run_span.span_type).to eq('web')
          expect(run_span.service).to eq(tracer.default_service)
          expect(run_span.resource).to eq('TestingAPI GET /widgets')
          expect(run_span).to_not have_error
          expect(run_span).to be_root_span
          expect(run_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('grape')
          expect(run_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq('endpoint_run')

          expect(run_span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_METHOD)).to eq('GET')
          expect(run_span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_URL)).to eq('/widgets')

          expect(run_span.get_tag(Datadog::Tracing::Contrib::Grape::Ext::TAG_ROUTE_PATH)).to eq('/widgets')
          expect(run_span.get_tag(Datadog::Tracing::Contrib::Grape::Ext::TAG_ROUTE_METHOD)).to eq('GET')
        end
      end

      context 'post method' do
        subject(:response) { post '/widgets' }

        it_behaves_like 'measured span for integration', true do
          before { expect(response.status).to eq(201) }
        end

        it_behaves_like 'analytics for integration', ignore_global_flag: false do
          let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Grape::Ext::ENV_ANALYTICS_ENABLED }
          let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Grape::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          before { expect(response.status).to eq(201) }
        end

        it 'traces the endpoint body' do
          expect(response.status).to eq(201)
          expect(response.body).to eq('{}')
          expect(spans.length).to eq(2)

          expect(render_span.name).to eq('grape.endpoint_render')
          expect(render_span.span_type).to eq('template')
          expect(render_span.service).to eq(tracer.default_service)
          expect(render_span.resource).to eq('grape.endpoint_render')
          expect(render_span).to_not have_error
          expect(render_span.parent_id).to eq(run_span.span_id)
          expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('grape')
          expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq('endpoint_render')

          expect(run_span.name).to eq('grape.endpoint_run')
          expect(run_span.span_type).to eq('web')
          expect(run_span.service).to eq(tracer.default_service)
          expect(run_span.resource).to eq('TestingAPI POST /widgets')
          expect(run_span).to_not have_error
          expect(run_span).to be_root_span
          expect(run_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('grape')
          expect(run_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq('endpoint_run')

          expect(run_span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_METHOD)).to eq('POST')
          expect(run_span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_URL)).to eq('/widgets')

          expect(run_span.get_tag(Datadog::Tracing::Contrib::Grape::Ext::TAG_ROUTE_PATH)).to eq('/widgets')
          expect(run_span.get_tag(Datadog::Tracing::Contrib::Grape::Ext::TAG_ROUTE_METHOD)).to eq('POST')
        end
      end

      context 'deeply nested' do
        subject(:response) { get '/nested/widgets' }

        it 'traces the endpoint body' do
          is_expected.to be_ok
          expect(response.body).to eq('[]')
          expect(spans.length).to eq(2)

          expect(render_span.name).to eq('grape.endpoint_render')
          expect(render_span.span_type).to eq('template')
          expect(render_span.service).to eq(tracer.default_service)
          expect(render_span.resource).to eq('grape.endpoint_render')
          expect(render_span).to_not have_error
          expect(render_span.parent_id).to eq(run_span.span_id)
          expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('grape')
          expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq('endpoint_render')

          expect(run_span.name).to eq('grape.endpoint_run')
          expect(run_span.span_type).to eq('web')
          expect(run_span.service).to eq(tracer.default_service)
          expect(run_span.resource).to eq('TestingAPI GET /nested/widgets')
          expect(run_span).to_not have_error
          expect(run_span).to be_root_span
          expect(run_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('grape')
          expect(run_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq('endpoint_run')

          expect(run_span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_METHOD)).to eq('GET')
          expect(run_span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_URL)).to eq('/nested/widgets')

          expect(run_span.get_tag(Datadog::Tracing::Contrib::Grape::Ext::TAG_ROUTE_PATH)).to eq('/nested/widgets')
          expect(run_span.get_tag(Datadog::Tracing::Contrib::Grape::Ext::TAG_ROUTE_METHOD)).to eq('GET')
        end
      end
    end

    describe 'span resource' do
      subject(:response) { get '/span_resource/span_resource' }

      before do
        is_expected.to be_ok
      end

      it 'sets the request (root) span resource before calling the endpoint' do
        expect(trace.name).to eq('grape.endpoint_run')
        expect(trace.resource).to eq('TestingAPI GET /span_resource/span_resource')
      end
    end

    context 'when tracing is disabled' do
      subject(:response) { get '/base/success' }

      before do
        Datadog.configure { |c| c.tracing.enabled = false }
        expect(Datadog.logger).to_not receive(:error)
      end

      it 'runs the endpoint request without tracing' do
        is_expected.to be_ok
        expect(response.body).to eq('OK')
        expect(spans.length).to eq(0)
      end
    end
  end

  context 'with rack' do
    let(:app) { rack_testing_api }
    let(:with_rack) { true }

    context 'success' do
      subject(:response) { get '/api/success' }

      it_behaves_like 'measured span for integration', true do
        before { is_expected.to be_ok }
      end

      it_behaves_like 'analytics for integration', ignore_global_flag: false do
        before { is_expected.to be_ok }

        let(:span) { spans.find { |x| x.name == Datadog::Tracing::Contrib::Grape::Ext::SPAN_ENDPOINT_RUN } }
        let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Grape::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Grape::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end

      it 'integrates with the Rack integration' do
        is_expected.to be_ok
        expect(response.body).to eq('OK')
        expect(trace).to_not be nil
        expect(spans.length).to eq(3)

        render_span, run_span, rack_span = spans

        expect(trace.resource).to eq('RackTestingAPI GET /success')

        expect(render_span.name).to eq('grape.endpoint_render')
        expect(render_span.span_type).to eq('template')
        expect(render_span.service).to eq(tracer.default_service)
        expect(render_span.resource).to eq('grape.endpoint_render')
        expect(render_span).to_not have_error
        expect(render_span.parent_id).to eq(run_span.span_id)
        expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('grape')
        expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq('endpoint_render')

        expect(run_span.name).to eq('grape.endpoint_run')
        expect(run_span.span_type).to eq('web')
        expect(run_span.service).to eq(tracer.default_service)
        expect(run_span.resource).to eq('RackTestingAPI GET /success')
        expect(run_span).to_not have_error
        expect(run_span.parent_id).to eq(rack_span.span_id)
        expect(run_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('grape')
        expect(run_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq('endpoint_run')

        expect(run_span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_METHOD)).to eq('GET')
        expect(run_span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_URL)).to eq('/success')

        expect(run_span.get_tag(Datadog::Tracing::Contrib::Grape::Ext::TAG_ROUTE_PATH)).to eq('/success')
        expect(run_span.get_tag(Datadog::Tracing::Contrib::Grape::Ext::TAG_ROUTE_METHOD)).to eq('GET')

        expect(rack_span.name).to eq('rack.request')
        expect(rack_span.span_type).to eq('web')
        expect(rack_span.service).to eq(tracer.default_service)
        expect(rack_span.resource).to eq('RackTestingAPI GET /success')
        expect(rack_span).to_not have_error
        expect(rack_span).to be_root_span
      end
    end

    context 'failure' do
      subject(:response) { get '/api/hard_failure' }

      it_behaves_like 'measured span for integration', true do
        before do
          expect { subject }.to raise_error(StandardError, 'Ouch!')
        end
      end

      it_behaves_like 'analytics for integration', ignore_global_flag: false do
        let(:span) { spans.find { |x| x.name == Datadog::Tracing::Contrib::Grape::Ext::SPAN_ENDPOINT_RUN } }
        let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Grape::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Grape::Ext::ENV_ANALYTICS_SAMPLE_RATE }
        before do
          expect { subject }.to raise_error(StandardError, 'Ouch!')
        end
      end

      it 'integrates with Rack integration when exception is thrown' do
        expect { subject }.to raise_error(StandardError, 'Ouch!')
        expect(trace).to_not be nil
        expect(spans.length).to eq(3)

        render_span, run_span, rack_span = spans

        expect(trace.resource).to eq('RackTestingAPI GET /hard_failure')

        expect(render_span.name).to eq('grape.endpoint_render')
        expect(render_span.span_type).to eq('template')
        expect(render_span.service).to eq(tracer.default_service)
        expect(render_span.resource).to eq('grape.endpoint_render')
        expect(render_span).to have_error
        expect(render_span).to have_error_type('StandardError')
        expect(render_span).to have_error_message('Ouch!')
        expect(render_span.get_tag('error.stack')).to include('grape/tracer_spec.rb')
        expect(render_span.parent_id).to eq(run_span.span_id)
        expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('grape')
        expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq('endpoint_render')

        expect(run_span.name).to eq('grape.endpoint_run')
        expect(run_span.span_type).to eq('web')
        expect(run_span.service).to eq(tracer.default_service)
        expect(run_span.resource).to eq('RackTestingAPI GET /hard_failure')
        expect(run_span).to have_error
        expect(run_span.parent_id).to eq(rack_span.span_id)
        expect(run_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('grape')
        expect(run_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq('endpoint_run')

        expect(run_span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_METHOD)).to eq('GET')
        expect(run_span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_URL)).to eq('/hard_failure')

        expect(run_span.get_tag(Datadog::Tracing::Contrib::Grape::Ext::TAG_ROUTE_PATH)).to eq('/hard_failure')
        expect(run_span.get_tag(Datadog::Tracing::Contrib::Grape::Ext::TAG_ROUTE_METHOD)).to eq('GET')

        expect(rack_span.name).to eq('rack.request')
        expect(rack_span.span_type).to eq('web')
        expect(rack_span.service).to eq(tracer.default_service)
        expect(rack_span.resource).to eq('RackTestingAPI GET /hard_failure')
        expect(rack_span).to have_error
        expect(rack_span).to be_root_span
      end
    end

    context 'missing route' do
      subject(:response) { get '/api/not_existing' }

      it_behaves_like 'measured span for integration', true do
        before do
          expect(subject.status).to eq(404)
        end
      end

      it 'does not impact the Rack integration that must work as usual' do
        expect(subject.status).to eq(404)
        expect(spans.length).to eq(1)

        rack_span = spans[0]

        expect(rack_span.name).to eq('rack.request')
        expect(rack_span.span_type).to eq('web')
        expect(rack_span.service).to eq(tracer.default_service)
        expect(rack_span.resource).to eq('GET 404')
        expect(rack_span).to_not have_error
        expect(rack_span).to be_root_span
      end
    end

    describe 'span resource' do
      subject(:response) { get '/api/span_resource_rack/span_resource' }

      before do
        is_expected.to be_ok
      end

      it 'sets the request (grape) span resource before calling the endpoint' do
        run_span = spans.find { |s| s.name == 'grape.endpoint_run' }
        expect(run_span.name).to eq('grape.endpoint_run')
        expect(run_span.resource).to eq('RackTestingAPI GET /span_resource_rack/span_resource')
      end

      it 'sets the trace resource before calling the endpoint' do
        expect(trace.resource).to eq('RackTestingAPI GET /span_resource_rack/span_resource')
      end
    end
  end
end
