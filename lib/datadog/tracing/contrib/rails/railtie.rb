require_relative 'framework'
require_relative 'middlewares'
require_relative '../rack/middlewares'

module Datadog
  # Railtie class initializes
  class Railtie < Rails::Railtie
    # Add the trace middleware to the application stack
    initializer 'datadog.before_intialize' do |app|
      Tracing::Contrib::Rails::Patcher.before_intialize(app)
    end

    config.after_initialize do
      Tracing::Contrib::Rails::Patcher.after_intialize(self)
    end
  end
end
