require 'contrib/rails/apps/application'

module Rails5
  class Application < RailsTrace::TestApplication
  end
end

def initialize_rails!
  Rails5::Application.test_config()
end

def rails_initialized?
  Rails.application.initialized?
end
