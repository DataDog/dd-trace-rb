# frozen_string_literal: true

require 'json'

require_relative '../../../core/configuration/base'
require_relative '../../../core/utils/only_once'
require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module Configuration
        # Common settings for all integrations
        # @public_api
        class Settings
          include Core::Configuration::Base

          QUANTIZE_SYMBOL_VALUES = {
            base: %w[exclude show],
            exclude: %w[all],
            fragment: %w[show],
            obfuscate: %w[internal],
            regex: %w[internal],
            show: %w[all],
          }.freeze

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

          private

          def parse_quantize_env(value)
            normalize_quantize_env(Core::Configuration::Option.parse_json_env(value))
          end

          def normalize_quantize_env(value, key = nil)
            case value
            when ::Hash
              value.each_with_object({}) do |(sub_key, sub_value), hash|
                normalized_key = sub_key.is_a?(String) ? sub_key.to_sym : sub_key
                hash[normalized_key] = normalize_quantize_env(sub_value, normalized_key)
              end
            when Array
              value.map { |item| normalize_quantize_env(item, key) }
            when String
              if QUANTIZE_SYMBOL_VALUES.fetch(key, []).include?(value)
                value.to_sym
              elsif key == :regex
                Regexp.new(value)
              else
                value
              end
            else
              value
            end
          rescue RegexpError => e
            raise ArgumentError, e.message
          end
        end
      end
    end
  end
end
