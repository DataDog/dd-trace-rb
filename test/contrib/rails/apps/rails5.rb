require 'rails/all'
require 'rails/test_help'
require 'action_view/testing/resolvers'

module Rails5
  class Application < Rails::Application
    config.secret_key_base = 'not_so_secret'

    routes.append do
      get '/' => 'welcome#index'
    end
  end
end

class WelcomeController < ActionController::Base
  include Rails.application.routes.url_helpers

  layout 'application'

  self.view_paths = [
    ActionView::FixtureResolver.new(
      'layouts/application.html.erb' => '<%= yield %>',
      'welcome/index.html.erb' => 'Hello from index.html.erb'
    )
  ]

  def index
  end
end

Rails5::Application.initialize!
