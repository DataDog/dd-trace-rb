# frozen_string_literal: true

require_relative "../../../core/configuration/base"
require_relative "../../../core/utils/only_once"

module Datadog
  module Tracing
    module Contrib
      module Configuration
        # Common settings for all integrations
        # @public_api
        class Settings
          include Core::Configuration::Base

          option :analytics_enabled, default: false
          option :analytics_sample_rate, default: 1.0
          option :enabled, default: true
          # TODO: Deprecate per-integration service name when first-class peer service support is added
          # TODO: We don't want to recommend per-integration service naming, but there are no equivalent alternatives today.
          option :service_name do |o|
            o.type :string, nilable: true
          end

          def configure(options = {})
            self.class.options.each_key do |name|
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

          # Copies the named options that are configured on another integration's settings,
          # keeping the precedence of each value. Options still at their default on the
          # source are left unchanged, and a copied value does not replace a value of higher
          # precedence.
          #
          # @param source_settings settings of the integration to copy values from
          # @param option_names names of the options, identical on both integrations
          # @!visibility private
          def copy_configured_options(source_settings, option_names)
            option_names.each do |name|
              next if source_settings.using_default?(name)

              precedence = source_settings.options.fetch(name).precedence_set
              set_option(name, source_settings[name], precedence: precedence)
            end
          end
        end
      end
    end
  end
end
