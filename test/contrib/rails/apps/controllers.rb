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
      'views/tracing/_body.html.erb' => '_body.html.erb partial'
    )
  ]

  def index
    render 'views/tracing/index.html.erb'
  end

  def partial
    render 'views/tracing/partial.html.erb'
  end

  def full
    @value = Rails.cache.read('empty-key')
    render 'views/tracing/full.html.erb'
  end
end

Rails.application.routes.append do
  get '/' => 'tracing#index'
  get '/partial' => 'tracing#partial'
  get '/full' => 'tracing#full'
end
