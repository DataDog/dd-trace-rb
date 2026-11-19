# frozen_string_literal: true

require_relative "connection"
require_relative "ext"
require_relative "rack_builder"
require_relative "../patcher"

module Datadog
  module Tracing
    module Contrib
      module Faraday
        # Patcher enables patching of 'faraday' module.
        module Patcher
          include Contrib::Patcher

          def self.target_version
            Integration.version
          end

          def self.patch
            require_relative "middleware"

            register_middleware!
            add_default_middleware!
          end

          def self.register_middleware!
            ::Faraday::Middleware.register_middleware(datadog_tracing: Middleware)
          end

          def self.add_default_middleware!
            if target_version >= Gem::Version.new("1.0.0")
              # Patch the default connection (e.g. +Faraday.get+)
              ::Faraday.default_connection.use(:datadog_tracing)

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
