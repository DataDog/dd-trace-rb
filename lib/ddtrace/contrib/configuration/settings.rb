# typed: false
require 'ddtrace/configuration/base'
require 'ddtrace/utils/only_once'

module Datadog
  module Contrib
    module Configuration
      # Common settings for all integrations
      class Settings
        include Datadog::Configuration::Base

        DEPRECATION_WARN_ONLY_ONCE = Datadog::Utils::OnlyOnce.new

        option :analytics_enabled, default: false
        option :analytics_sample_rate, default: 1.0
        option :enabled, default: true
        option :service_name # TODO: remove suffix "_name"

        def configure(options = {})
          self.class.options.dependency_order.each do |name|
            self[name] = options[name] if options.key?(name)
          end

          yield(self) if block_given?
        end

        def [](name)
          respond_to?(name) ? send(name) : get_option(name)
        end

        def []=(name, value)
          respond_to?("#{name}=") ? send("#{name}=", value) : set_option(name, value)
        end
      end
    end
  end
end
