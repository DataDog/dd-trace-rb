require 'contrib/rails/apps/application'

module Rails4
  class Application < RailsTrace::TestApplication
    config.active_support.test_order = :random
  end
end

def initialize_rails!
  Rails4::Application.test_config
end

def rails_initialized?
  Rails.application.initialized?
end
