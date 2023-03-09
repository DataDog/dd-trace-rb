require 'datadog/tracing/contrib/rails/rails_helper'

RSpec.describe 'Rails Rack' do
  include Rack::Test::Methods
  include_context 'Rails test application'

  let(:routes) do
    {
      '/full' => 'test#full',
      '/partial' => 'test#partial',
      '/nonexistent_template' => 'test#nonexistent_template',
      '/nonexistent_partial' => 'test#nonexistent_partial',
      '/error' => 'test#error',
      '/sub_error' => 'test#sub_error',
      '/soft_error' => 'test#soft_error',
      '/error_handled_by_rescue_from' => 'test#error_handled_by_rescue_from',
      '/error_template' => 'test#error_template',
      '/error_partial' => 'test#error_partial',
      '/internal_server_error' => 'errors#internal_server_error',
      '/span_resource' => 'test#span_resource',
      '/custom_span_resource' => 'test#custom_span_resource',
      '/explicitly_not_found' => 'test#explicitly_not_found',
    }
  end

  let(:layout) { 'application' }
  let(:controllers) { [controller, errors_controller] }
  let(:controller) do
    layout_ = layout
    stub_const('RescuableError', Class.new(StandardError))
    stub_const(
      'TestController',
      Class.new(ActionController::Base) do
        include ::Rails.application.routes.url_helpers

        layout layout_

        self.view_paths = [ActionView::FixtureResolver.new(
          'layouts/application.html.erb' => '<%= yield %>',
          'test/full.html.erb' => 'Test template content',
          'test/template_with_partial.html.erb' => 'Template with <%= render "test/outer_partial" %>',
          'test/partial_does_not_exist.html.erb' => '<%= render "test/no_partial_here" %>',
          'test/_outer_partial.html.erb' => 'a partial inside <%= render "test/inner_partial" %>',
          'test/_inner_partial.html.erb' => 'a partial',
          'test/error_template.html.erb' => '<%= 1/0 %>',
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

        def nonexistent_template
          render 'does_not_exist'
        end

        def nonexistent_partial
          render 'partial_does_not_exist'
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

        def error_handled_by_rescue_from
          raise RescuableError
        end

        rescue_from 'RescuableError' do
          render 'full'
        end

        def error_template
          render 'error_template'
        end

        def error_partial
          render 'error_partial'
        end

        define_method(:span_resource) do
          head :ok
        end

        def custom_span_resource
          Datadog::Tracing.active_span.resource = 'CustomSpanResource'

          head :ok
        end

        # Users can decide late in the request that a 404 is the desired outcome.
        def explicitly_not_found
          raise ActionController::RoutingError, :not_found
        end
      end
    )
  end
  let(:errors_controller) do
    stub_const(
      'ErrorsController',
      Class.new(ActionController::Base) do
        def internal_server_error
          head :internal_server_error
        end
      end
    )
  end

  context 'with a full request' do
    subject(:response) { get '/full' }

    it 'traces request' do
      is_expected.to be_ok

      expect(trace).to_not be nil
      expect(spans).to have(4).items

      # Spans are sorted alphabetically
      request_span, controller_span, cache_span, render_span = spans

      expect(trace.resource).to eq('TestController#full')

      expect(request_span.name).to eq('rack.request')
      expect(request_span.span_type).to eq('web')
      expect(request_span.service).to eq(tracer.default_service)
      expect(request_span.resource).to eq('TestController#full')
      expect(request_span.get_tag('http.url')).to eq('/full')
      expect(request_span.get_tag('http.method')).to eq('GET')
      expect(request_span.get_tag('http.status_code')).to eq('200')
      expect(request_span).to be_measured
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('rack')
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('request')

      expect(controller_span.name).to eq('rails.action_controller')
      expect(controller_span.span_type).to eq('web')
      expect(controller_span.service).to eq(tracer.default_service)
      expect(controller_span.resource).to eq('TestController#full')
      expect(controller_span.get_tag('rails.route.action')).to eq('full')
      expect(controller_span.get_tag('rails.route.controller')).to eq('TestController')
      expect(controller_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('action_pack')
      expect(controller_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('controller')
      expect(controller_span).to be_measured

      expect(cache_span.name).to eq('rails.cache')
      expect(cache_span.span_type).to eq('cache')
      expect(cache_span.resource).to eq('SET')
      expect(cache_span.service).to eq('active_support-cache')
      expect(cache_span.get_tag('rails.cache.backend').to_s).to eq('file_store')
      expect(cache_span.get_tag('rails.cache.key')).to eq('empty-key')
      expect(cache_span).to_not be_measured

      expect(render_span.name).to eq('rails.render_template')
      expect(render_span.span_type).to eq('template')
      expect(render_span.service).to eq(tracer.default_service)
      expect(render_span.resource).to eq('full.html.erb')
      expect(render_span.get_tag('rails.template_name')).to eq('full.html.erb')
      expect(render_span.get_tag('rails.layout')).to eq('layouts/application')
      expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('action_view')
      expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('render_template')
      expect(render_span).to be_measured
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

        expect(render_span.resource).to eq('full.html.erb')
        expect(render_span.get_tag('rails.template_name')).to eq('full.html.erb')
        expect(render_span.get_tag('rails.layout')).to be_nil
        expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('action_view')
        expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('render_template')
      end
    end
  end

  context 'with a partial templates' do
    subject(:response) { get '/partial' }

    it do
      is_expected.to be_ok
      expect(spans).to have(5).items

      _rack_span, _controller_span, inner_partial_span, outer_partial_span, template_span = spans

      expect(inner_partial_span.name).to eq('rails.render_partial')
      expect(inner_partial_span.span_type).to eq('template')
      expect(inner_partial_span.resource).to eq('_inner_partial.html.erb')
      expect(inner_partial_span.get_tag('rails.template_name')).to eq('_inner_partial.html.erb')
      expect(inner_partial_span).to be_measured
      expect(inner_partial_span.parent_id).to eq(outer_partial_span.span_id)
      expect(inner_partial_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('action_view')
      expect(inner_partial_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('render_partial')

      expect(outer_partial_span.name).to eq('rails.render_partial')
      expect(outer_partial_span.span_type).to eq('template')
      expect(outer_partial_span.resource).to eq('_outer_partial.html.erb')
      expect(outer_partial_span.get_tag('rails.template_name')).to eq('_outer_partial.html.erb')
      expect(outer_partial_span).to be_measured
      expect(outer_partial_span.parent_id).to eq(template_span.span_id)
      expect(inner_partial_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('action_view')
      expect(inner_partial_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('render_partial')
    end

    it 'tracing does not affect response body' do
      expect(response.body).to eq('Template with a partial inside a partial')
    end
  end

  context 'trying to render a nonexistent template' do
    subject(:response) { get '/nonexistent_template' }

    before do
      skip 'Recent versions use events, and cannot suffer from this issue' if Rails.version >= '4.0.0'
    end

    it 'traces complete stack' do
      is_expected.to be_server_error

      expect(trace).to_not be nil
      expect(spans).to have(3).items
      request_span, controller_span, template_span = spans

      expect(trace.resource).to eq('TestController#nonexistent_template')

      expect(request_span.name).to eq('rack.request')
      expect(request_span.resource).to eq('TestController#nonexistent_template')
      expect(request_span).to have_error
      expect(request_span).to have_error_type('ActionView::MissingTemplate')
      expect(request_span).to have_error_message(include('Missing template test/does_not_exist'))
      expect(request_span).to have_error_stack
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('rack')
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('request')

      expect(controller_span.name).to eq('rails.action_controller')
      expect(controller_span.resource).to eq('TestController#nonexistent_template')
      expect(controller_span).to have_error
      expect(controller_span).to have_error_type('ActionView::MissingTemplate')
      expect(controller_span).to have_error_message(include('Missing template test/does_not_exist'))
      expect(controller_span).to have_error_stack
      expect(controller_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('action_pack')
      expect(controller_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('controller')

      expect(template_span.name).to eq('rails.render_template')
      expect(template_span.resource).to eq('rails.render_template') # Fallback value due to missing template
      expect(template_span.span_type).to eq('template')
      expect(template_span.get_tag('rails.template_name')).to be_nil
      expect(template_span.get_tag('rails.layout')).to be_nil
      expect(template_span).to have_error
      expect(template_span).to have_error_type('ActionView::MissingTemplate')
      expect(template_span).to have_error_message(include('Missing template test/does_not_exist'))
      expect(template_span).to have_error_stack
      expect(template_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('action_view')
      expect(template_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('render_template')
    end
  end

  context 'trying to render a nonexistent partial template' do
    subject(:response) { get '/nonexistent_partial' }

    before do
      skip 'Recent versions use events, and cannot suffer from this issue' if Rails.version >= '4.0.0'
    end

    it 'traces complete stack' do
      is_expected.to be_server_error

      expect(trace).to_not be nil
      expect(spans).to have(4).items

      request_span, controller_span, partial_span, template_span = spans

      expect(trace.resource).to eq('TestController#nonexistent_partial')

      expect(request_span.name).to eq('rack.request')
      expect(request_span.resource).to eq('TestController#nonexistent_partial')
      expect(request_span).to have_error
      expect(request_span).to have_error_type('ActionView::Template::Error')
      expect(request_span).to have_error_message(include('Missing partial test/no_partial_here'))
      expect(request_span).to have_error_stack
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('rack')
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('request')

      expect(controller_span.name).to eq('rails.action_controller')
      expect(controller_span.resource).to eq('TestController#nonexistent_partial')
      expect(controller_span).to have_error
      expect(controller_span).to have_error_type('ActionView::Template::Error')
      expect(controller_span).to have_error_message(include('Missing partial test/no_partial_here'))
      expect(controller_span).to have_error_stack
      expect(controller_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('action_pack')
      expect(controller_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('controller')

      expect(partial_span.name).to eq('rails.render_partial')
      expect(partial_span.resource).to eq('rails.render_partial') # Fallback value due to missing partial
      expect(partial_span.span_type).to eq('template')
      expect(partial_span.get_tag('rails.template_name')).to be_nil
      expect(partial_span.get_tag('rails.layout')).to be_nil
      expect(partial_span).to have_error
      expect(partial_span).to have_error_type('ActionView::MissingTemplate')
      expect(partial_span).to have_error_message(include('Missing partial test/no_partial_here'))
      expect(partial_span).to have_error_stack
      expect(partial_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('action_view')
      expect(partial_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('render_partial')

      expect(template_span.name).to eq('rails.render_template')
      expect(template_span.resource).to eq('partial_does_not_exist.html.erb') # Fallback value due to missing template
      expect(template_span.span_type).to eq('template')
      expect(template_span.get_tag('rails.template_name')).to eq('partial_does_not_exist.html.erb')
      expect(template_span.get_tag('rails.layout')).to eq('layouts/application')
      expect(template_span).to have_error
      expect(template_span).to have_error_type('ActionView::Template::Error')
      expect(template_span).to have_error_message(include('Missing partial test/no_partial_here'))
      expect(template_span).to have_error_stack
      expect(template_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('action_view')
      expect(template_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('render_template')
    end
  end

  context 'with a controller exception' do
    subject { get '/error' }

    it 'traces with error information' do
      is_expected.to be_server_error

      expect(trace).to_not be nil
      expect(spans).to have(2).items
      request_span, controller_span = spans

      expect(trace.resource).to eq('TestController#error')

      expect(request_span.name).to eq('rack.request')
      expect(request_span.span_type).to eq('web')
      expect(request_span.resource).to eq('TestController#error')
      expect(request_span.get_tag('http.url')).to eq('/error')
      expect(request_span.get_tag('http.method')).to eq('GET')
      expect(request_span.get_tag('http.status_code')).to eq('500')
      expect(request_span).to have_error
      expect(request_span).to have_error_stack(match(/rack_spec\.rb.*\berror\b/))
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('rack')
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('request')

      expect(controller_span.name).to eq('rails.action_controller')
      expect(controller_span).to have_error
      expect(controller_span).to have_error_type('ZeroDivisionError')
      expect(controller_span).to have_error_message('divided by 0')
      expect(controller_span).to have_error_stack
      expect(controller_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('action_pack')
      expect(controller_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('controller')
    end
  end

  context 'with a soft controller error' do
    subject { get '/soft_error' }

    it 'traces without explicit exception information' do
      is_expected.to be_server_error

      expect(trace).to_not be nil
      expect(spans).to have_at_least(2).items
      request_span, controller_span = spans

      expect(trace.resource).to eq('TestController#soft_error')

      expect(request_span.name).to eq('rack.request')
      expect(request_span.span_type).to eq('web')
      expect(request_span.resource).to eq('TestController#soft_error')
      expect(request_span.get_tag('http.url')).to eq('/soft_error')
      expect(request_span.get_tag('http.method')).to eq('GET')
      expect(request_span.get_tag('http.status_code')).to eq('520')
      expect(request_span).to have_error
      expect(request_span).to_not have_error_stack
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('rack')
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('request')

      expect(controller_span.name).to eq('rails.action_controller')
      expect(controller_span).to have_error
      expect(controller_span).to_not have_error_type
      expect(controller_span).to_not have_error_message
      expect(controller_span).to_not have_error_stack
      expect(controller_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('action_pack')
      expect(controller_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('controller')
    end
  end

  context 'with a nested controller error' do
    subject { get '/sub_error' }

    it 'traces complete stack' do
      is_expected.to be_server_error

      expect(trace).to_not be nil
      expect(spans).to have(2).items
      request_span, controller_span = spans

      expect(trace.resource).to eq('TestController#sub_error')

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
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('rack')
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('request')

      expect(controller_span.name).to eq('rails.action_controller')
      expect(controller_span).to have_error
      expect(controller_span).to have_error_type('ZeroDivisionError')
      expect(controller_span).to have_error_message('divided by 0')
      expect(controller_span).to have_error_stack
      expect(controller_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('action_pack')
      expect(controller_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('controller')
    end
  end

  context 'with a controller error handled by rescue_from' do
    subject { get '/error_handled_by_rescue_from' }

    it 'does not propagate error status to Rack span' do
      is_expected.to be_ok

      expect(trace).to_not be nil
      expect(spans).to have(3).items
      request_span, controller_span, _template_span = spans

      expect(trace.resource).to eq('TestController#error_handled_by_rescue_from')

      expect(request_span.name).to eq('rack.request')
      expect(request_span.span_type).to eq('web')
      expect(request_span.get_tag('http.method')).to eq('GET')
      expect(request_span.get_tag('http.status_code')).to eq('200')
      expect(request_span).to_not have_error
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('rack')
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('request')

      expect(controller_span.name).to eq('rails.action_controller')
      expect(controller_span).to have_error
      expect(controller_span).to have_error_type('RescuableError')
      expect(controller_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('action_pack')
      expect(controller_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('controller')
    end
  end

  context 'with custom error controllers' do
    subject do
      # Simulate an error being passed to the exception controller
      get '/internal_server_error', {}, 'action_dispatch.exception' => ArgumentError.new
    end

    it 'does not override trace resource names' do
      is_expected.to be_server_error

      expect(trace).to_not be nil
      expect(spans).to have(2).items
      request_span, controller_span = spans

      expect(trace.resource).to eq('ErrorsController#internal_server_error')

      expect(request_span).to have_error
      expect(request_span.resource).to eq('ErrorsController#internal_server_error')
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('rack')
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('request')

      expect(controller_span).to have_error
      expect(controller_span.resource).to eq('ErrorsController#internal_server_error')
      expect(controller_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('action_pack')
      expect(controller_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('controller')
    end
  end

  context 'without hitting controller' do
    subject { get '/this_route_does_not_exist' }

    it 'sets status code' do
      is_expected.to be_not_found

      expect(trace).to_not be nil
      expect(spans).to have_at_least(1).item
      request_span = spans[0]

      expect(trace.resource).to eq('GET 404')

      expect(request_span.name).to eq('rack.request')
      expect(request_span.span_type).to eq('web')
      expect(request_span.resource).to eq('GET 404')
      expect(request_span.get_tag('http.url')).to eq('/this_route_does_not_exist')
      expect(request_span.get_tag('http.method')).to eq('GET')
      expect(request_span.get_tag('http.status_code')).to eq('404')
      expect(request_span).to_not have_error
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('rack')
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('request')
    end
  end

  context 'with an explicitly raised 404' do
    subject { get '/explicitly_not_found' }

    it 'does captures the attempted URL information' do
      is_expected.to be_not_found

      expect(trace).to_not be nil
      expect(spans).to have_at_least(1).item
      request_span = spans[0]

      expect(trace.resource).to eq('TestController#explicitly_not_found')

      expect(request_span.name).to eq('rack.request')
      expect(request_span.span_type).to eq('web')
      expect(request_span.resource).to eq('TestController#explicitly_not_found')
      expect(request_span.get_tag('http.url')).to eq('/explicitly_not_found')
      expect(request_span.get_tag('http.method')).to eq('GET')
      expect(request_span.get_tag('http.status_code')).to eq('404')
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('rack')
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('request')
    end

    it 'does not mark rack span as error' do
      is_expected.to be_not_found

      request_span = spans[0]
      expect(request_span).to_not have_error
    end
  end

  context 'with error rendering a template' do
    subject { get '/error_template' }

    it 'has ActionView error tags' do
      is_expected.to be_server_error

      expect(trace).to_not be nil
      expect(spans).to have(3).items
      request_span, controller_span, render_span = spans

      expect(trace.resource).to eq('TestController#error_template')

      expect(request_span).to have_error
      expect(request_span).to have_error_type('ActionView::Template::Error')
      expect(request_span).to have_error_stack
      expect(request_span).to have_error_message
      expect(request_span.resource).to eq('TestController#error_template')
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('rack')
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('request')

      expect(controller_span).to have_error
      expect(controller_span).to have_error_type('ActionView::Template::Error')
      expect(controller_span).to have_error_stack
      expect(controller_span).to have_error_message
      expect(controller_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('action_pack')
      expect(controller_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('controller')

      expect(render_span.name).to eq('rails.render_template')
      expect(render_span.span_type).to eq('template')
      expect(render_span.resource).to eq('error_template.html.erb')
      expect(render_span.get_tag('rails.template_name')).to eq('error_template.html.erb')
      expect(render_span.get_tag('rails.layout')).to eq('layouts/application')
      expect(render_span).to have_error
      expect(render_span).to have_error_type('ActionView::Template::Error')
      expect(render_span).to have_error_message('divided by 0')
      expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('action_view')
      expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('render_template')
    end
  end

  context 'with error rendering partial template' do
    subject { get '/error_partial' }

    it 'has ActionView error tags' do
      is_expected.to be_server_error

      expect(trace).to_not be nil
      expect(spans).to have(4).items
      request_span, controller_span, partial_span, render_span = spans

      expect(trace.resource).to eq('TestController#error_partial')

      expect(request_span).to have_error
      expect(request_span).to have_error_type('ActionView::Template::Error')
      expect(request_span).to have_error_stack
      expect(request_span).to have_error_message
      expect(request_span.resource).to eq('TestController#error_partial')
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('rack')
      expect(request_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('request')

      expect(controller_span).to have_error
      expect(controller_span).to have_error_type('ActionView::Template::Error')
      expect(controller_span).to have_error_stack
      expect(controller_span).to have_error_message
      expect(controller_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('action_pack')
      expect(controller_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('controller')

      expect(partial_span.name).to eq('rails.render_partial')
      expect(partial_span.span_type).to eq('template')
      expect(partial_span.resource).to eq('_inner_error.html.erb')
      expect(partial_span.get_tag('rails.template_name')).to include('_inner_error.html')
      expect(partial_span.get_tag('rails.layout')).to be_nil
      expect(partial_span).to have_error
      expect(partial_span).to have_error_type('ActionView::Template::Error')
      expect(partial_span).to have_error_message('divided by 0')
      expect(partial_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('action_view')
      expect(partial_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('render_partial')

      expect(render_span).to have_error
      expect(render_span).to have_error_type('ActionView::Template::Error')
      expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('action_view')
      expect(render_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('render_template')
    end
  end

  describe 'span resource' do
    subject(:response) { get '/span_resource' }

    before do
      is_expected.to be_ok
    end

    it 'sets the controller span resource before calling the controller' do
      controller_span = spans.find { |s| s.name == 'rails.action_controller' }
      expect(controller_span.name).to eq('rails.action_controller')
      expect(controller_span.resource).to eq('TestController#span_resource')
    end

    it 'sets the trace resource before calling the controller' do
      expect(trace.resource).to eq('TestController#span_resource')
    end

    context 'a custom controller span resource is applied' do
      subject(:response) { get '/custom_span_resource' }

      it 'propagates the custom controller span resource to the request span resource' do
        expect(trace.resource).to eq('CustomSpanResource')
      end
    end
  end
end
