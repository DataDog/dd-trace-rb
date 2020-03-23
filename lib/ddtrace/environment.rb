require 'ddtrace/ext/environment'

module Datadog
  # Namespace for handling application environment
  module Environment
    # TODO: Extract to Datadog::Configuration::Settings
    def self.env
      ENV[Ext::Environment::ENV_ENVIRONMENT]
    end

    # TODO: Extract to Datadog::Configuration::Settings
    def self.tags
      tags = {}

      env_to_list(Ext::Environment::ENV_TAGS).each do |tag|
        pair = tag.split(':')
        tags[pair.first] = pair.last if pair.length == 2
      end

      tags[Ext::Environment::TAG_ENV] = env unless env.nil?
      tags[Ext::Environment::TAG_VERSION] = version unless version.nil?

      tags
    end

    def self.version
      ENV[Ext::Environment::ENV_VERSION]
    end

    # Defines helper methods for environment
    module Helpers
      def env_to_bool(var, default = nil)
        ENV.key?(var) ? ENV[var].to_s.downcase == 'true' : default
      end

      def env_to_float(var, default = nil)
        ENV.key?(var) ? ENV[var].to_f : default
      end

      def env_to_list(var, default = [])
        if ENV.key?(var)
          ENV[var].split(',').map(&:strip)
        else
          default
        end
      end
    end

    extend Helpers
  end
end
