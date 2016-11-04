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

Rails.application.routes.append do
  get '/' => 'tracing#index'
  get '/partial' => 'tracing#partial'
  get '/full' => 'tracing#full'
  get '/error' => 'tracing#error'
  get '/error_template' => 'tracing#error_template'
  get '/error_partial' => 'tracing#error_partial'
end
