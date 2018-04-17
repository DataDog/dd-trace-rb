require 'ddtrace/contrib/active_record/configuration/handler'

module Datadog
  module Contrib
    module ActiveRecord
      # Provides some configuration functions for ActiveRecord tracing.
      module Configuration
        module_function

        def database_settings(spec)
          database_settings_handler.get(spec)
        end

        def database_settings=(config)
          database_settings_handler.tap do |handler|
            config.each do |spec, settings|
              handler.set(spec, settings)
            end
          end
        end

        def clear_database_settings!
          @database_settings_handler = ::Datadog::Contrib::ActiveRecord::Configuration::Handler.new
        end

        def database_settings_handler
          @database_settings_handler ||= ::Datadog::Contrib::ActiveRecord::Configuration::Handler.new
        end
      end
    end
  end
end
