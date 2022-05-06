# typed: false

require 'datadog/tracing/contrib/faraday/connection'
require 'datadog/tracing/contrib/faraday/ext'
require 'datadog/tracing/contrib/faraday/rack_builder'
require 'datadog/tracing/contrib/patcher'

module Datadog
  module Tracing
    module Contrib
      module Faraday
        # Patcher enables patching of 'faraday' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            require 'datadog/tracing/contrib/faraday/middleware'

            register_middleware!
            add_default_middleware!
          end

          def register_middleware!
            ::Faraday::Middleware.register_middleware(ddtrace: Middleware)
          end

          def add_default_middleware!
            if target_version >= Gem::Version.new('1.0.0')
              # Patch the default connection (e.g. +Faraday.get+)
              ::Faraday.default_connection.use(:ddtrace)

              # Patch new connection instances (e.g. +Faraday.new+)
              ::Faraday::Connection.prepend(Connection)
            else
              # Patch the default connection (e.g. +Faraday.get+)
              #
              # We insert our middleware before the 'adapter', which is
              # always the last handler.
              idx = ::Faraday.default_connection.builder.handlers.size - 1
              ::Faraday.default_connection.builder.insert(idx, Middleware)

              # Patch new connection instances (e.g. +Faraday.new+)
              ::Faraday::RackBuilder.prepend(RackBuilder)
            end
          end
        end
      end
    end
  end
end
