require 'action_view/testing/resolvers'

class TracingController < ActionController::Base
  include Rails.application.routes.url_helpers

  layout 'application'

  self.view_paths = [
    ActionView::FixtureResolver.new(
      'layouts/application.html.erb' => '<%= yield %>',
      'tracing/index.html.erb' => 'Hello from index.html.erb',
      'tracing/partial.html.erb' => 'Hello from <%= render "partials/body.html.erb" %>',
      'tracing/full.html.erb' => '<% @articles.each do |article| %><% end %>',
      'partials/_body.html.erb' => 'body.html.erb'
    )
  ]

  def index
  end

  def partial
  end

  def full
    @articles = Article.all
    @value = Rails.cache.read('empty-key')
  end
end

Rails.application.routes.append do
  get '/' => 'tracing#index'
  get '/partial' => 'tracing#partial'
  get '/full' => 'tracing#full'
end
