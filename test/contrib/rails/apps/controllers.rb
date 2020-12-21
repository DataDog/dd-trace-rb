require 'action_view/testing/resolvers'

# ActionText requires an ApplicationController to be defined since Rails 6
class ApplicationController < ActionController::Base; end

class TracingController < ActionController::Base
  rescue_from 'ActionController::RenderError' do
    render 'views/tracing/index.html.erb'
  end

  include Rails.application.routes.url_helpers

  layout 'application'

  self.view_paths = [
    ActionView::FixtureResolver.new(
      'layouts/application.html.erb' => '<%= yield %>',
      'views/tracing/index.html.erb' => 'Hello from index.html.erb',
      'views/tracing/partial.html.erb' => 'Hello from <%= render "views/tracing/body" %>',
      'views/tracing/full.html.erb' => '<% Article.all.each do |article| %><% end %>',
      'views/tracing/error.html.erb' => '<%= 1/0 %>',
      'views/tracing/missing_partial.html.erb' => '<%= render "ouch.html.erb" %>',
      'views/tracing/soft_error.html.erb' => 'nothing',
      'views/tracing/not_found.html.erb' => 'nothing',
      'views/tracing/error_partial.html.erb' => 'Hello from <%= render "views/tracing/inner_error" %>',
      'views/tracing/nested_partial.html.erb' => 'Server says (<%= render "views/tracing/outer_partial" %>)',
      'views/tracing/_outer_partial.html.erb' => 'Outer partial: (<%= render "views/tracing/inner_partial" %>)',
      'views/tracing/_inner_partial.html.erb' => 'Inner partial',
      'views/tracing/_body.html.erb' => '_body.html.erb partial',
      'views/tracing/_inner_error.html.erb' => '<%= 1/0 %>'
    )
  ]

  def index
    render 'views/tracing/index'
  end

  def partial
    render 'views/tracing/partial'
  end

  def nested_partial
    render 'views/tracing/nested_partial'
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

  def not_found
    # Here we raise manually a 'Not Found' exception.
    # The conversion is by default done by Rack::Utils.status_code using
    # http://www.rubydoc.info/gems/rack/Rack/Utils#HTTP_STATUS_CODES-constant
    raise ActionController::RoutingError, :not_found
  end

  def error_template
    render 'views/tracing/error'
  end

  def missing_template
    render 'views/tracing/ouch_not_here'
  end

  def missing_partial
    render 'views/tracing/missing_partial'
  end

  def error_partial
    render 'views/tracing/error_partial'
  end

  def full
    @value = Rails.cache.write('empty-key', 50)
    render 'views/tracing/full'
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
end
