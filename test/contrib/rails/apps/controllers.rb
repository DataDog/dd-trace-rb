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
      'views/tracing/sub_error.html.erb' => '<%= 1/0 %>',
      'views/tracing/soft_error.html.erb' => 'nothing',
      'views/tracing/not_found.html.erb' => 'nothing',
      'views/tracing/error_partial.html.erb' => 'Hello from <%= render "views/tracing/inner_error.html.erb" %>',
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

  def error_partial
    render 'views/tracing/error_partial.html.erb'
  end

  def full
    @value = Rails.cache.write('empty-key', 50)
    render 'views/tracing/full.html.erb'
  end
end

routes = {
  '/' => 'tracing#index',
  '/partial' => 'tracing#partial',
  '/full' => 'tracing#full',
  '/error' => 'tracing#error',
  '/soft_error' => 'tracing#soft_error',
  '/sub_error' => 'tracing#sub_error',
  '/not_found' => 'tracing#not_found',
  '/error_template' => 'tracing#error_template',
  '/error_partial' => 'tracing#error_partial'
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
