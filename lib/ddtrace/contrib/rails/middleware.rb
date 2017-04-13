module Datadog
  module Contrib
    module Rails
      class Middleware

        def initialize(app)
          @app = app
        end

        def call(env)
          @app.call(env)
        end
      end
    end
  end
end
