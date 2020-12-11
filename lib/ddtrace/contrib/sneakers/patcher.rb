# frozen_string_literal: true

require 'ddtrace/contrib/sneakers/tracer'

module Datadog
  module Contrib
    module Sneakers
      # Patcher enables patching of 'sneakers' module.
      module Patcher
        include Datadog::Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        def patch
          ::Sneakers.middleware.use(Sneakers::Tracer, nil)
        end
      end
    end
  end
end
