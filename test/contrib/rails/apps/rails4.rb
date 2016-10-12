require 'contrib/rails/apps/application'

require 'ddtrace'

module Rails4
  class Application < RailsTrace::TestApplication
    config.active_support.test_order = :random
  end
end

Rails4::Application.test_config()
