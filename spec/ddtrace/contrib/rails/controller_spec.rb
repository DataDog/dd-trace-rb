require 'ddtrace/contrib/rails/rails_helper'

require 'action_view/testing/resolvers'

def tracing_controller
  stub_const('TracingController', Class.new(ActionController::Base) do
    include Rails.application.routes.url_helpers

    layout 'application'

    self.view_paths = [
      ActionView::FixtureResolver.new(
        'layouts/application.html.erb' => '<%= yield %>',
        'views/tracing/index.html.erb' => 'Hello from index.html.erb',
        'views/tracing/partial.html.erb' => 'Hello from <%= render "views/tracing/body.html.erb" %>',
        'views/tracing/full.html.erb' => '<% Article.all.each do |article| %><% end %>',
        'views/tracing/error.html.erb' => '<%= 1/0 %>',
        'views/tracing/missing_partial.html.erb' => '<%= render "ouch.html.erb" %>',
        'views/tracing/sub_error.html.erb' => '<%= 1/0 %>',
        'views/tracing/soft_error.html.erb' => 'nothing',
        'views/tracing/not_found.html.erb' => 'nothing',
        'views/tracing/error_partial.html.erb' => 'Hello from <%= render "views/tracing/inner_error.html.erb" %>',
        'views/tracing/nested_partial.html.erb' => 'Server says (<%= render "views/tracing/outer_partial.html.erb" %>)',
        'views/tracing/_outer_partial.html.erb' => 'Outer partial: (<%= render "views/tracing/inner_partial.html.erb" %>)',
        'views/tracing/_inner_partial.html.erb' => 'Inner partial',
        'views/tracing/_body.html.erb' => '_body.html.erb partial',
        'views/tracing/_inner_error.html.erb' => '<%= 1/0 %>'
      )
    ]

    def index
      render 'views/tracing/index.html.erb'
    end

    def partial
      render 'views/tracing/partial.html.erb'
    end

    def nested_partial
      render 'views/tracing/nested_partial.html.erb'
    end

    def error
      1 / 0
    end

    def soft_error
      if Rails::VERSION::MAJOR.to_i >= 5
        head 520
      else
        render nothing: true, status: 520
      end
    end

    def sub_error
      a_nested_error_call
    end

    def a_nested_error_call
      another_nested_error_call
    end

    def another_nested_error_call
      error
    end

    def not_found
      # Here we raise manually a 'Not Found' exception.
      # The conversion is by default done by Rack::Utils.status_code using
      # http://www.rubydoc.info/gems/rack/Rack/Utils#HTTP_STATUS_CODES-constant
      raise ActionController::RoutingError, :not_found
    end

    def error_template
      render 'views/tracing/error.html.erb'
    end

    def missing_template
      render 'views/tracing/ouch.not.here'
    end

    def missing_partial
      render 'views/tracing/missing_partial.html.erb'
    end

    def error_partial
      render 'views/tracing/error_partial.html.erb'
    end

    def full
      @value = Rails.cache.write('empty-key', 50)
      render 'views/tracing/full.html.erb'
    end

    def custom_resource
      tracer = Datadog.configuration[:rails][:tracer]
      tracer.active_span.resource = 'custom-resource'
      head :ok
    end

    def custom_tag
      tracer = Datadog.configuration[:rails][:tracer]
      tracer.active_span.set_tag('custom-tag', 'custom-tag-value')

      head :ok
    end
  end)
end

ROUTES =
  {
    '/' => 'tracing#index',
    '/nested_partial' => 'tracing#nested_partial',
    '/partial' => 'tracing#partial',
    '/full' => 'tracing#full',
    '/error' => 'tracing#error',
    '/soft_error' => 'tracing#soft_error',
    '/sub_error' => 'tracing#sub_error',
    '/not_found' => 'tracing#not_found',
    '/error_template' => 'tracing#error_template',
    '/error_partial' => 'tracing#error_partial',
    '/missing_template' => 'tracing#missing_template',
    '/missing_partial' => 'tracing#missing_partial',
    '/custom_resource' => 'tracing#custom_resource',
    '/custom_tag' => 'tracing#custom_tag',
    '/internal_server_error' => 'errors#internal_server_error'
  }

# TODO move back to controller test only?
RSpec.describe 'Rails application' do
  include Rack::Test::Methods
  include_context 'Rails test application'
  include_context 'Tracer'

  before do
    @original_tracer = Datadog.configuration[:rails][:tracer]
    Datadog.configuration[:rails][:tracer] = tracer
  end

  after do
    Datadog.configuration[:rails][:tracer] = @original_tracer
  end

  let(:routes) { ROUTES }

  let(:controllers) { [controller] }

  let(:controller) do
    # stub_const('TestController', Class.new(ActionController::Base) do
    #   def index
    #     head :ok
    #   end
    # end)

    tracing_controller
  end

  before { app }

  it 'request is properly traced' do
    # make the request and assert the proper span
    get '/'
    expect(last_response).to be_ok
    expect(spans).to have(3).items

    span = spans.second
    expect(span.name).to eq('rails.action_controller')
    expect(span.span_type).to eq('web')
    expect(span.resource).to eq('TracingController#index')
    expect(span.get_tag('rails.route.action')).to eq('index')
    expect(span.get_tag('rails.route.controller')).to eq('TracingController')
  end

  it 'template tracing does not break the code' do
    # render a template and expect the correct result
    get '/'
    expect(last_response).to be_ok
    expect(last_response.body).to eq('Hello from index.html.erb')
  end

  it 'template partial tracing does not break the code' do
    # render a partial and expect the correct result
    get '/partial'
    expect(last_response).to be_ok
    expect(last_response.body).to eq('Hello from _body.html.erb partial')
  end

  it 'template rendering is properly traced' do
    # render the template and assert the proper span
    get '/'
    expect(last_response).to be_ok
    expect(spans).to have(3).items

    span = spans.last
    expect(span.name).to eq('rails.render_template')
    expect(span.span_type).to eq('template')
    expect(span.resource).to eq('rails.render_template')
    expect(span.get_tag('rails.template_name')).to eq('tracing/index.html.erb') if Rails.version >= '3.2.22.5'
    expect(span.get_tag('rails.template_name')).to include('tracing/index.html')
    expect(span.get_tag('rails.layout')).to eq('layouts/application') if Rails.version >= '3.2.22.5'
    expect(span.get_tag('rails.layout')).to include('layouts/application')
  end

  it 'template partial rendering is properly traced' do
    # render the template and assert the proper span
    get '/partial'
    expect(last_response).to be_ok
    expect(spans).to have(3).items

    _, span_partial, span_template = spans
    expect(span_partial.name).to eq('rails.render_partial')
    expect(span_partial.span_type).to eq('template')
    expect(span_partial.resource).to eq('rails.render_partial')
    assert_equal(span_partial.get_tag('rails.template_name'), 'tracing/_body.html.erb') if Rails.version >= '3.2.22.5'
    assert_includes(span_partial.get_tag('rails.template_name'), 'tracing/_body.html')
    expect(span_partial.parent).to eq(span_template)
  end

  it 'template nested partial rendering is properly traced' do
    # render the template and assert the proper span
    get '/nested_partial'
    expect(last_response).to be_ok

    # Verify all spans have closed
    expect(tracer.call_context.trace.all?(&:finished?)).to be_truthy

    # Verify correct number of spans
    spans = tracer.writer.spans
    expect(spans.length).to have(4).items

    _, span_outer_partial, span_inner_partial, span_template = spans

    # Outer partial
    expect('rails.render_partial').to eq(span_outer_partial.name)
    expect('template').to eq(span_outer_partial.span_type)
    expect('rails.render_partial').to eq(span_outer_partial.resource)
    if Rails.version >= '3.2.22.5'
      expect('tracing/_outer_partial.html.erb').to eq(span_outer_partial.get_tag('rails.template_name'))
    end
    assert_includes(span_outer_partial.get_tag('rails.template_name'), 'tracing/_outer_partial.html')
    expect(span_template).to eq(span_outer_partial.parent)

    # Inner partial
    expect('rails.render_partial').to eq(span_inner_partial.name)
    expect('template').to eq(span_inner_partial.span_type)
    expect('rails.render_partial').to eq(span_inner_partial.resource)
    if Rails.version >= '3.2.22.5'
      expect('tracing/_inner_partial.html.erb').to eq(span_inner_partial.get_tag('rails.template_name'))
    end
    assert_includes(span_inner_partial.get_tag('rails.template_name'), 'tracing/_inner_partial.html')
    expect(span_outer_partial).to eq(span_inner_partial.parent)
  end

  it 'a full request with database access on the template' do
    # render the endpoint
    get '/full'
    expect(last_response).to be_ok
    spans = tracer.writer.spans

    # rubocop:disable Style/IdenticalConditionalBranches
    if Datadog::Contrib::ActiveRecord::Events::Instantiation.supported?
      expect(spans.length).to have(5).items
      span_instantiation, span_database, span_request, span_cache, span_template = spans

      # assert the spans
      adapter_name = get_adapter_name
      expect(span_instantiation.name).to eq('active_record.instantiation')
      expect(span_cache.name).to eq('rails.cache')
      expect(span_database.name).to eq("#{adapter_name}.query")
      expect(span_template.name).to eq('rails.render_template')
      expect(span_request.name).to eq('rails.action_controller')

      # assert the parenting
      expect(span_request.parent).to be_nil
      expect(span_template.parent).to eq(span_request)
      expect(span_database.parent).to eq(span_template)
      expect(span_instantiation.parent).to eq(span_template)
      expect(span_cache.parent).to eq(span_request)
    else
      expect(spans.length).to have(4).items
      span_database, span_request, span_cache, span_template = spans

      # assert the spans
      adapter_name = get_adapter_name
      expect(span_cache.name).to eq('rails.cache')
      expect(span_database.name).to eq("#{adapter_name}.query")
      expect(span_template.name).to eq('rails.render_template')
      expect(span_request.name).to eq('rails.action_controller')

      # assert the parenting
      expect(span_request.parent).to be_nil
      expect(span_template.parent).to eq(span_request)
      expect(span_database.parent).to eq(span_template)
      expect(span_cache.parent).to eq(span_request)
    end
  end

  it 'multiple calls should not leave an unfinished span in the local thread buffer' do
    get '/full'
    expect(last_response).to be_ok
    expect(Thread.current[:datadog_span]).to be_nil

    get '/full'
    expect(last_response).to be_ok
    expect(Thread.current[:datadog_span]).to be_nil
  end

  it 'error should be trapped and reported as such' do
    get '/error'
    expect(last_response).to be_server_error

    expect('rails.action_controller').to eq(span.name)
    expect(1).to eq(span.status)
    expect('ZeroDivisionError').to eq(span.get_tag('error.type'))
    expect('divided by 0').to eq(span.get_tag('error.msg'))
    refute_nil(span.get_tag('error.stack'))
  end

  it 'not found error should not be reported as an error' do
    get '/not_found'
    expect(last_response).to be_client_error
    expect('rails.action_controller').to eq(span.name)

    # Rails 3.0 doesn't know how to convert exceptions to 'not found'
    # Expect newer versions to correctly not flag this span.
    if Rails.version >= '3.2'
      expect(0).to eq(span.status)
      expect(span.get_tag('error.type')).to be_nil
      expect(span.get_tag('error.msg')).to be_nil
      expect(span.get_tag('error.stack')).to be_nil
    end
  end

  it 'http error code should be trapped and reported as such, even with no exception' do
    get '/soft_error'

    span = spans.second
    expect('rails.action_controller').to eq(span.name)
    expect(span.status).to eq(1)
    expect(span.get_tag('error.type')).to be_nil
    expect(span.get_tag('error.msg')).to be_nil
    expect(span.get_tag('error.stack')).to be_nil
  end

  it 'custom resource names can be set' do
    get '/custom_resource'
    expect(last_response).to be_ok

    expect('custom-resource').to eq(spans.last.resource)
  end

  it 'custom tags can be set' do
    get '/custom_tag'
    expect(last_response).to be_ok

    expect('custom-tag-value').to eq(spans.last.get_tag('custom-tag'))
  end

  it 'combining rails and custom tracing is supported' do
    # TODO not with RACK!
    tracer.trace('a-parent') do
      get '/'
      expect(last_response).to be_ok
      tracer.trace('a-brother') do
      end
    end

    expect(spans).to have(5).items

    brother_span, parent_span, rack_span, controller_span, = spans
    expect('rails.action_controller').to eq(controller_span.name)
    expect('web').to eq(controller_span.span_type)
    expect('TracingController#index').to eq(controller_span.resource)
    expect('index').to eq(controller_span.get_tag('rails.route.action'))
    expect('TracingController').to eq(controller_span.get_tag('rails.route.controller'))
    expect('a-parent').to eq(parent_span.name)
    expect('a-brother').to eq(brother_span.name)
    expect(controller_span.trace_id).to eq(parent_span.trace_id)
    expect(controller_span.trace_id).to eq(brother_span.trace_id)
    expect(parent_span.span_id).to eq(controller_span.parent_id)
    expect(brother_span.parent_id).to eq(controller_span.parent_id)
  end
end
