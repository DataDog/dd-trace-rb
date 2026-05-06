# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module Sinatra
        # Rack middleware for AppSec on Sinatra
        class RequestMiddleware
          # TODO: opt is never used, it can probably be safely removed
          def initialize(app, opt = {}) # steep:ignore DifferentMethodParameterKind
            @app = app
          end

          def call(env)
            @app.call(env)
          end
        end
      end
    end
  end
end
