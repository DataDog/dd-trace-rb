# typed: false
require 'ddtrace/configuration/base'
require 'ddtrace/utils/only_once'

module Datadog
  module Contrib
    module Configuration
      # Common settings for all integrations
      # @public_api
      class Settings
        include Datadog::Configuration::Base

        DEPRECATION_WARN_ONLY_ONCE = Datadog::Utils::OnlyOnce.new

        # @public_api
        option :analytics_enabled, default: false
        # @public_api
        option :analytics_sample_rate, default: 1.0
        # @public_api
        option :enabled, default: true
        # @public_api
        option :service_name # TODO: remove suffix "_name"

        # @public_api
        def configure(options = {})
          self.class.options.dependency_order.each do |name|
            self[name] = options[name] if options.key?(name)
          end

          yield(self) if block_given?
        end

        # @public_api
        def [](name)
          respond_to?(name) ? send(name) : get_option(name)
        end

        # @public_api
        def []=(name, value)
          respond_to?("#{name}=") ? send("#{name}=", value) : set_option(name, value)
        end
      end
    end
  end
end
