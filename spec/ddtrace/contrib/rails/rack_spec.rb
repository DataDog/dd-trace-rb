require 'ddtrace/contrib/rails/rails_helper'

RSpec.describe 'Rails Rack' do
  include Rack::Test::Methods
  include_context 'Rails test application'

  let(:routes) do
    {
      '/full' => 'test#full',
      '/partial' => 'test#partial',
      '/error' => 'test#error',
      '/sub_error' => 'test#sub_error',
      '/soft_error' => 'test#soft_error',
      '/error_handled_by_rescue_from' => 'test#error_handled_by_rescue_from',
      '/error_partial' => 'test#error_partial',
      '/internal_server_error' => 'errors#internal_server_error'
    }
  end

  let(:layout) { 'application' }
  let(:controllers) { [controller, errors_controller] }
  let(:controller) do
    layout_ = layout
    stub_const('TestController', Class.new(ActionController::Base) do
      include ::Rails.application.routes.url_helpers

      layout layout_

      self.view_paths = [ActionView::FixtureResolver.new(
        'layouts/application.html.erb' => '<%= yield %>',
        'test/full.html.erb' => 'Test template content',
        'test/template_with_partial.html.erb' => 'Template with <%= render "test/outer_partial" %>',
        'test/_outer_partial.html.erb' => 'a partial inside <%= render "test/inner_partial" %>',
        'test/_inner_partial.html.erb' => 'a partial',
        'test/error_partial.html.erb' => 'Oops <%= render "test/inner_error" %>',
        'test/_inner_error.html.erb' => '<%= 1/0 %>'
      )]

      def full
        @value = ::Rails.cache.write('empty-key', 50)
        render 'full'
      end

      def partial
        render 'template_with_partial'
      end

      def error
        1 / 0
      end

      def sub_error
        error
      end

      def soft_error
        if Rails::VERSION::MAJOR.to_i >= 5
          head 520
        else
          render nothing: true, status: 520
        end
      end

      RescuableError = Class.new(StandardError)

      def error_handled_by_rescue_from
        raise RescuableError
      end

      rescue_from 'RescuableError' do
        render 'full'
      end

      def error_partial
        render 'error_partial'
      end
    end)
  end
  let(:errors_controller) do
    stub_const('ErrorsController', Class.new(ActionController::Base) do
      def internal_server_error
        head :internal_server_error
      end
    end)
  end

  let(:controller_spans) do
    expect(spans).to have_at_least(2).items
    spans
  end

  let(:request_span) { spans[0] }
  let(:controller_span) { spans[1] }

  context 'with a full request' do
    subject(:response) { get '/full' }

    it 'traces request' do
      is_expected.to be_ok

      expect(spans).to have(4).items

      # Spans are sorted alphabetically
      request_span, controller_span, cache_span, render_span = spans

      expect(request_span.name).to eq('rack.request')
      expect(request_span.span_type).to eq('web')
      expect(request_span.resource).to eq('TestController#full')
      expect(request_span.get_tag('http.url')).to eq('/full')
      expect(request_span.get_tag('http.method')).to eq('GET')
      expect(request_span.get_tag('http.status_code')).to eq('200')
      expect(request_span).to be_measured

      expect(controller_span.name).to eq('rails.action_controller')
      expect(controller_span.span_type).to eq('web')
      expect(controller_span.resource).to eq('TestController#full')
      expect(controller_span.get_tag('rails.route.action')).to eq('full')
      expect(controller_span.get_tag('rails.route.controller')).to eq('TestController')
      expect(controller_span).to be_measured

      expect(render_span.name).to eq('rails.render_template')
      expect(render_span.span_type).to eq('template')
      expect(render_span.service).to eq(Datadog.configuration[:rails][:service_name])
      expect(render_span.resource).to eq('full.html.erb')
      expect(render_span.get_tag('rails.template_name')).to eq('full.html.erb')
      expect(render_span.get_tag('rails.layout')).to eq('layouts/application') if Rails.version >= '3.2.22.5'
      expect(render_span.get_tag('rails.layout')).to include('layouts/application')
      expect(render_span).to be_measured

      expect(cache_span.name).to eq('rails.cache')
      expect(cache_span.span_type).to eq('cache')
      expect(cache_span.resource).to eq('SET')
      expect(cache_span.service).to eq("#{app_name}-cache")
      expect(cache_span.get_tag('rails.cache.backend').to_s).to eq('file_store')
      expect(cache_span.get_tag('rails.cache.key')).to eq('empty-key')
      expect(cache_span).to_not be_measured
    end

    it 'tracing does not affect response body' do
      expect(response.body).to eq('Test template content')
    end

    context 'without explicit layout' do
      # Most users of Rails do not explicitly specify a controller layout
      let(:layout) { nil }

      it do
        is_expected.to be_ok
        expect(spans).to have(4).items

        # Spans are sorted alphabetically
        _request_span, _controller_span, _cache_span, render_span = spans

        expect(render_span.resource).to eq('full.html.erb') if Rails.version >= '3.2.22.5'
        expect(render_span.resource).to include('full.html')
        expect(render_span.get_tag('rails.template_name')).to eq('full.html.erb') if Rails.version >= '3.2.22.5'
        expect(render_span.get_tag('rails.template_name')).to include('full.html')
        expect(render_span.get_tag('rails.layout')).to be_nil
      end
    end
  end

  context 'with a partial templates' do
    subject(:response) { get '/partial' }

    it do
      is_expected.to be_ok
      expect(spans).to have(5).items

      _rack_span, _controller_span, inner_partial_span, outer_partial_span, template_span = spans

      expect(outer_partial_span.name).to eq('rails.render_partial')
      expect(outer_partial_span.span_type).to eq('template')
      expect(outer_partial_span.resource).to eq('_outer_partial.html.erb')
      if Rails.version >= '3.2.22.5'
        expect(outer_partial_span.get_tag('rails.template_name')).to eq('_outer_partial.html.erb')
      end
      expect(outer_partial_span.get_tag('rails.template_name')).to include('_outer_partial.html')
      expect(outer_partial_span).to be_measured
      expect(outer_partial_span.parent).to eq(template_span)

      expect(inner_partial_span.name).to eq('rails.render_partial')
      expect(inner_partial_span.span_type).to eq('template')
      expect(inner_partial_span.resource).to eq('_inner_partial.html.erb')
      if Rails.version >= '3.2.22.5'
        expect(inner_partial_span.get_tag('rails.template_name')).to eq('_inner_partial.html.erb')
      end
      expect(inner_partial_span.get_tag('rails.template_name')).to include('_inner_partial.html')
      expect(inner_partial_span).to be_measured
      expect(inner_partial_span.parent).to eq(outer_partial_span)
    end

    it 'tracing does not affect response body' do
      expect(response.body).to eq('Template with a partial inside a partial')
    end
  end

  context 'with a controller exception' do
    subject { get '/error' }

    it 'traces with error information' do
      is_expected.to be_server_error

      expect(controller_span.name).to eq('rails.action_controller')
      expect(controller_span).to have_error
      expect(controller_span).to have_error_type('ZeroDivisionError')
      expect(controller_span).to have_error_message('divided by 0')
      expect(controller_span).to have_error_stack

      expect(request_span.name).to eq('rack.request')
      expect(request_span.span_type).to eq('web')
      expect(request_span.resource).to eq('TestController#error')
      expect(request_span.get_tag('http.url')).to eq('/error')
      expect(request_span.get_tag('http.method')).to eq('GET')
      expect(request_span.get_tag('http.status_code')).to eq('500')
      expect(request_span).to have_error
      expect(request_span).to have_error_stack(match(/rack_spec\.rb.*\berror\b/))
    end
  end

  context 'with a soft controller error' do
    subject { get '/soft_error' }

    it 'traces without explicit exception information' do
      is_expected.to be_server_error

      expect(controller_span.name).to eq('rails.action_controller')
      expect(controller_span).to have_error
      expect(controller_span).to_not have_error_type
      expect(controller_span).to_not have_error_message
      expect(controller_span).to_not have_error_stack

      expect(request_span.name).to eq('rack.request')
      expect(request_span.span_type).to eq('web')
      expect(request_span.resource).to eq('TestController#soft_error')
      expect(request_span.get_tag('http.url')).to eq('/soft_error')
      expect(request_span.get_tag('http.method')).to eq('GET')
      expect(request_span.get_tag('http.status_code')).to eq('520')
      expect(request_span).to have_error
      expect(request_span).to_not have_error_stack
    end
  end

  context 'with a nested controller error' do
    subject { get '/sub_error' }

    it 'traces complete stack' do
      is_expected.to be_server_error

      expect(controller_span.name).to eq('rails.action_controller')
      expect(controller_span).to have_error
      expect(controller_span).to have_error_type('ZeroDivisionError')
      expect(controller_span).to have_error_message('divided by 0')
      expect(controller_span).to have_error_stack

      expect(request_span.name).to eq('rack.request')
      expect(request_span.span_type).to eq('web')
      expect(request_span.resource).to eq('TestController#sub_error')
      expect(request_span.get_tag('http.url')).to eq('/sub_error')
      expect(request_span.get_tag('http.method')).to eq('GET')
      expect(request_span.get_tag('http.status_code')).to eq('500')
      expect(request_span).to have_error
      expect(request_span).to have_error_type('ZeroDivisionError')
      expect(request_span).to have_error_message('divided by 0')
      expect(request_span).to have_error_stack(match(/rack_spec\.rb.*\berror\b/))
      expect(request_span).to have_error_stack(match(/rack_spec\.rb.*\bsub_error\b/))
    end
  end

  context 'with a controller error handled by rescue_from' do
    subject { get '/error_handled_by_rescue_from' }

    it 'does not propagate error status to Rack span' do
      is_expected.to be_ok

      expect(controller_span.name).to eq('rails.action_controller')
      expect(controller_span).to have_error
      expect(controller_span).to have_error_type('RescuableError')

      expect(request_span.name).to eq('rack.request')
      expect(request_span.span_type).to eq('web')
      expect(request_span.get_tag('http.method')).to eq('GET')
      expect(request_span.get_tag('http.status_code')).to eq('200')
      expect(request_span).to_not have_error
    end
  end

  context 'with custom error controllers' do
    subject do
      # Simulate an error being passed to the exception controller
      get '/internal_server_error', {}, 'action_dispatch.exception' => ArgumentError.new
    end

    it 'does not override trace resource names' do
      is_expected.to be_server_error

      expect(controller_span).to have_error
      expect(controller_span.resource).to eq('ErrorsController#internal_server_error')

      expect(request_span).to have_error
      expect(request_span.resource).to_not eq(controller_span.resource)
    end
  end

  context 'without hitting controller' do
    subject { get '/this_route_does_not_exist' }

    it 'sets status code' do
      is_expected.to be_not_found

      expect(spans).to have_at_least(1).item
      request_span = spans[0]

      expect(request_span.name).to eq('rack.request')
      expect(request_span.span_type).to eq('web')
      expect(request_span.resource).to eq('GET 404')
      expect(request_span.get_tag('http.url')).to eq('/this_route_does_not_exist')
      expect(request_span.get_tag('http.method')).to eq('GET')
      expect(request_span.get_tag('http.status_code')).to eq('404')
      expect(request_span).to_not have_error
    end
  end

  context 'with error rendering partial template' do
    subject { get '/error_partial' }

    it 'has ActionView error tags' do
      is_expected.to be_server_error

      if Gem::Version.new(Rails::VERSION::STRING) < Gem::Version.new('3.2')
        expect(spans).to have(5).items

        # Rails 3.0 has an intermediate internal template file,
        # `_request_and_response.erb`, to handle exceptions.
        request_span, controller_span, partial_span, __request_and_response_span, render_span = spans
      else
        expect(spans).to have(4).items
        request_span, controller_span, partial_span, render_span = spans
      end

      expect(request_span).to have_error
      expect(request_span).to have_error_type('ActionView::Template::Error')
      expect(request_span).to have_error_stack
      expect(request_span).to have_error_message
      expect(request_span.resource).to_not eq(render_span.resource)

      expect(controller_span).to have_error
      expect(controller_span).to have_error_type('ActionView::Template::Error')
      expect(controller_span).to have_error_stack
      expect(controller_span).to have_error_message

      expect(render_span).to have_error
      expect(render_span).to have_error_type('ActionView::Template::Error')

      expect(partial_span).to have_error
      expect(partial_span).to have_error_type('ActionView::Template::Error')
    end
  end
end
