require 'ddtrace/contrib/active_record/configuration/resolver'

module Datadog
  module Contrib
    module ActiveRecord
      module Configuration
        # Resolves and stores configuration settings for connections
        class Handler
          def initialize(configurations = ::ActiveRecord::Base.configurations)
            @resolver = Resolver.new(configurations)
          end

          def get(spec)
            connection_config = @resolver.resolve(spec)
            settings[connection_config] || {}
          end

          def set(spec, settings)
            connection_config = @resolver.resolve(spec)
            self.settings[connection_config] = settings unless connection_config.nil?
          end

          def settings
            @settings ||= {}
          end
        end
      end
    end
  end
end
