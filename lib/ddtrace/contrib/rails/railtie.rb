# typed: ignore
require 'ddtrace/contrib/rails/framework'
require 'ddtrace/contrib/rails/middlewares'
require 'ddtrace/contrib/rack/middlewares'

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
