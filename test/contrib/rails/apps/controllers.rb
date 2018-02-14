require 'action_view/testing/resolvers'

class TracingController < ActionController::Base
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
end

class CallbacksController < ActionController::Base
  include Rails.application.routes.url_helpers

  if Rails.version >= '4.0'
    before_action :before_request
    after_action :after_request
  else
    before_filter :before_request
    after_filter :after_request
  end

  def index
    head :ok
  end

  def before_request
    # Sample before_action callback
  end

  def after_request
    # Sample after_action callback
  end
end

class ErrorsController < ActionController::Base
  def internal_server_error
    head :internal_server_error
  end
end

routes = {
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
  '/callbacks' => 'callbacks#index',
  '/internal_server_error' => 'errors#internal_server_error'
}

if Rails.version >= '3.2.22.5'
  Rails.application.routes.append do
    routes.each do |k, v|
      get k => v
    end
  end
else
  Rails.application.routes.draw do
    routes.each do |k, v|
      get k, to: v
    end
  end
end
