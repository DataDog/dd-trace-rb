require 'ddtrace/contrib/support/spec_helper'
require 'rack/test'
require 'ddtrace'
require 'ddtrace/contrib/grape/app'
require 'ddtrace/contrib/grape/rack_app'
require 'ddtrace/contrib/rack/middlewares'

RSpec.describe 'Grape instrumentation' do
  include Rack::Test::Methods

  let(:configuration_options) { {} }

  let(:render_span) { spans.find { |x| x.name == Datadog::Contrib::Grape::Ext::SPAN_ENDPOINT_RENDER } }
  let(:run_span) { spans.find { |x| x.name == Datadog::Contrib::Grape::Ext::SPAN_ENDPOINT_RUN } }
  let(:run_filter_span) { spans.find { |x| x.name == Datadog::Contrib::Grape::Ext::SPAN_ENDPOINT_RUN_FILTERS } }

  before do
    Datadog.configure do |c|
      c.use :rack, configuration_options if with_rack
      c.use :grape, configuration_options
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
    let(:app) { TestingAPI }

    let(:with_rack) { false }

    context 'success' do
      context 'without filters' do
        subject(:response) { get '/base/success' }

        it 'should trace the endpoint body' do
          is_expected.to be_ok
          expect(response.body).to eq('OK')
          expect(spans.length).to eq(2)

          expect(render_span.name).to eq('grape.endpoint_render')
          expect(render_span.span_type).to eq('template')
          expect(render_span.service).to eq('grape')
          expect(render_span.resource).to eq('grape.endpoint_render')
          expect(render_span.status).to eq(0)
          expect(render_span.parent).to eq(run_span)
          expect(render_span.get_metric('_dd.measured')).to eq(1.0)

          expect(run_span.name).to eq('grape.endpoint_run')
          expect(run_span.span_type).to eq('web')
          expect(run_span.service).to eq('grape')
          expect(run_span.resource).to eq('TestingAPI#success')
          expect(run_span.status).to eq(0)
          expect(run_span.parent).to be_nil
          expect(run_span.get_metric('_dd.measured')).to eq(1.0)
        end
      end

      context 'with filters' do
        subject(:response) { get '/filtered/before_after' }

        it 'should trace the endpoint body and all before/after filters' do
          is_expected.to be_ok
          expect(response.body).to eq('OK')
          expect(spans.length).to eq(4)

          render_span, run_span, before_span, after_span = spans

          expect(before_span.name).to eq('grape.endpoint_run_filters')
          expect(before_span.span_type).to eq('web')
          expect(before_span.service).to eq('grape')
          expect(before_span.resource).to eq('grape.endpoint_run_filters')
          expect(before_span.status).to eq(0)
          expect(before_span.parent).to eq(run_span)
          expect(before_span.to_hash[:duration] > 0.01).to be true
          expect(before_span.get_metric('_dd.measured')).to eq(1.0)

          expect(render_span.name).to eq('grape.endpoint_render')
          expect(render_span.span_type).to eq('template')
          expect(render_span.service).to eq('grape')
          expect(render_span.resource).to eq('grape.endpoint_render')
          expect(render_span.status).to eq(0)
          expect(render_span.parent).to eq(run_span)

          expect(after_span.name).to eq('grape.endpoint_run_filters')
          expect(after_span.span_type).to eq('web')
          expect(after_span.service).to eq('grape')
          expect(after_span.resource).to eq('grape.endpoint_run_filters')
          expect(after_span.status).to eq(0)
          expect(after_span.parent).to eq(run_span)
          expect(after_span.to_hash[:duration] > 0.01).to be true
          expect(after_span.get_metric('_dd.measured')).to eq(1.0)

          expect('grape.endpoint_run').to eq(run_span.name)
          expect('web').to eq(run_span.span_type)
          expect('grape').to eq(run_span.service)
          expect('TestingAPI#before_after').to eq(run_span.resource)
          expect(0).to eq(run_span.status)
          expect(run_span.parent).to be_nil
        end
      end
    end

    context 'failure' do
      context 'without filters' do
        subject(:response) { get '/base/hard_failure' }

        it 'should handle exceptions' do
          expect { subject }.to raise_error(StandardError, 'Ouch!')

          expect(spans.length).to eq(2)

          expect(render_span.name).to eq('grape.endpoint_render')
          expect(render_span.span_type).to eq('template')
          expect(render_span.service).to eq('grape')
          expect(render_span.resource).to eq('grape.endpoint_render')
          expect(render_span.status).to eq(1)

          expect(render_span.get_tag('error.type')).to eq('StandardError')
          expect(render_span.get_tag('error.msg')).to eq('Ouch!')
          expect(render_span.get_tag('error.stack')).to include('grape/app.rb')
          expect(render_span.parent).to eq(run_span)
          expect(render_span.get_metric('_dd.measured')).to eq(1.0)

          expect(run_span.name).to eq('grape.endpoint_run')
          expect(run_span.span_type).to eq('web')
          expect(run_span.service).to eq('grape')
          expect(run_span.resource).to eq('TestingAPI#hard_failure')
          expect(run_span.status).to eq(1)

          expect(run_span.get_tag('error.type')).to eq('StandardError')
          expect(run_span.get_tag('error.msg')).to eq('Ouch!')
          expect(run_span.get_tag('error.stack')).to include('grape/app.rb')
          expect(run_span.parent).to be_nil
          expect(run_span.get_metric('_dd.measured')).to eq(1.0)
        end
      end

      context 'with filters' do
        subject(:response) { get '/filtered_exception/before' }

        it 'should trace the endpoint even if a filter raises an exception' do
          expect { subject }.to raise_error(StandardError, 'Ouch!')

          expect(spans.length).to eq(2)

          run_span, before_span = spans

          expect(before_span.name).to eq('grape.endpoint_run_filters')
          expect(before_span.span_type).to eq('web')
          expect(before_span.service).to eq('grape')
          expect(before_span.resource).to eq('grape.endpoint_run_filters')
          expect(before_span.status).to eq(1)
          expect(before_span.get_tag('error.type')).to eq('StandardError')
          expect(before_span.get_tag('error.msg')).to eq('Ouch!')
          expect(before_span.get_tag('error.stack')).to include('grape/app.rb')
          expect(before_span.parent).to eq(run_span)

          expect(run_span.name).to eq('grape.endpoint_run')
          expect(run_span.span_type).to eq('web')
          expect(run_span.service).to eq('grape')
          expect(run_span.resource).to eq('TestingAPI#before')
          expect(run_span.status).to eq(1)
          expect(run_span.parent).to be_nil
        end
      end
    end
  end

  context 'with rack' do
    let(:app) do
      # create a custom Rack application with the Rack middleware and a Grape API
      Rack::Builder.new do
        use Datadog::Contrib::Rack::TraceMiddleware
        map '/api/' do
          run RackTestingAPI
        end
      end.to_app
    end

    let(:with_rack) { true }

    context 'success' do
      subject(:response) { get '/api/success' }

      it 'should intergrate with the Rack integration' do
        is_expected.to be_ok
        expect(response.body).to eq('OK')
        expect(spans.length).to eq(3)

        render_span, run_span, rack_span = spans

        expect(render_span.name).to eq('grape.endpoint_render')
        expect(render_span.span_type).to eq('template')
        expect(render_span.service).to eq('grape')
        expect(render_span.resource).to eq('grape.endpoint_render')
        expect(render_span.status).to eq(0)
        expect(render_span.parent).to eq(run_span)

        expect(run_span.name).to eq('grape.endpoint_run')
        expect(run_span.span_type).to eq('web')
        expect(run_span.service).to eq('grape')
        expect(run_span.resource).to eq('RackTestingAPI#success')
        expect(run_span.status).to eq(0)
        expect(run_span.parent).to eq(rack_span)

        expect(rack_span.name).to eq('rack.request')
        expect(rack_span.span_type).to eq('web')
        expect(rack_span.service).to eq('rack')
        expect(rack_span.resource).to eq('RackTestingAPI#success')
        expect(rack_span.status).to eq(0)
        expect(rack_span.parent).to be_nil
      end

      context 'failure' do
        subject(:response) { get '/api/hard_failure' }

        it 'should integrate with Racck integration when exception is thrown' do
          expect { subject }.to raise_error(StandardError, 'Ouch!')
          expect(spans.length).to eq(3)

          render_span, run_span, rack_span = spans

          expect(render_span.name).to eq('grape.endpoint_render')
          expect(render_span.span_type).to eq('template')
          expect(render_span.service).to eq('grape')
          expect(render_span.resource).to eq('grape.endpoint_render')
          expect(render_span.status).to eq(1)
          expect(render_span.get_tag('error.type')).to eq('StandardError')
          expect(render_span.get_tag('error.msg')).to eq('Ouch!')
          expect(render_span.get_tag('error.stack')).to include('grape/rack_app.rb')
          expect(render_span.parent).to eq(run_span)

          expect(run_span.name).to eq('grape.endpoint_run')
          expect(run_span.span_type).to eq('web')
          expect(run_span.service).to eq('grape')
          expect(run_span.resource).to eq('RackTestingAPI#hard_failure')
          expect(run_span.status).to eq(1)
          expect(run_span.parent).to eq(rack_span)

          expect(rack_span.name).to eq('rack.request')
          expect(rack_span.span_type).to eq('web')
          expect(rack_span.service).to eq('rack')
          expect(rack_span.resource).to eq('RackTestingAPI#hard_failure')
          expect(rack_span.status).to eq(1)
          expect(rack_span.parent).to be_nil
        end
      end

      context 'missing route' do
        subject(:response) { get '/api/not_existing' }

        it 'it should not impact the Rack integration that must work as usual' do
          expect(subject.status).to eq(404)
          expect(spans.length).to eq(1)

          rack_span = spans[0]

          expect(rack_span.name).to eq('rack.request')
          expect(rack_span.span_type).to eq('web')
          expect(rack_span.service).to eq('rack')
          expect(rack_span.resource).to eq('GET 404')
          expect(rack_span.status).to eq(0)
          expect(rack_span.parent).to be_nil
        end
      end
    end
  end
end
