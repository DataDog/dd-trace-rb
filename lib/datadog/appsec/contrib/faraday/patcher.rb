# frozen_string_literal: true

require_relative '../patcher'

module Datadog
  module AppSec
    module Contrib
      module Faraday
        # Patcher for Faraday
        module Patcher
          include Datadog::AppSec::Contrib::Patcher

          module_function

          def patched?
            Patcher.instance_variable_get(:@patched)
          end

          def target_version
            Integration.version
          end

          def patch
            require_relative 'middleware'
            require_relative 'connection'

            register_middleware!
            add_default_middleware!

            Patcher.instance_variable_set(:@patched, true)
          end

          def register_middleware!
            ::Faraday::Middleware.register_middleware(datadog_appsec: Middleware)
          end

          def add_default_middleware!
            if target_version >= Gem::Version.new('1.0.0')
              # Patch the default connection (e.g. +Faraday.get+)
              ::Faraday.default_connection.use(:datadog_appsec)

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
