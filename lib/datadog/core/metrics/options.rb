require_relative 'ext'
require_relative '../environment/ext'
require_relative '../environment/identity'

module Datadog
  module Core
    module Metrics
      # For defining and adding default options to metrics
      module Options
        DEFAULT = {
          tags: DEFAULT_TAGS = [
            "#{Ext::TAG_LANG}:#{Environment::Identity.lang}".freeze,
            "#{Ext::TAG_LANG_INTERPRETER}:#{Environment::Identity.lang_interpreter}".freeze,
            "#{Ext::TAG_LANG_VERSION}:#{Environment::Identity.lang_version}".freeze,
            "#{Ext::TAG_TRACER_VERSION}:#{Environment::Identity.tracer_version}".freeze
          ].freeze
        }.freeze

        def metric_options(options = nil)
          return default_metric_options if options.nil?

          default_metric_options.merge(options) do |key, old_value, new_value|
            case key
            when :tags
              old_value.dup.concat(new_value).uniq
            else
              new_value
            end
          end
        end

        def default_metric_options
          # Return dupes, so that the constant isn't modified,
          # and defaults are unfrozen for mutation in Statsd.
          DEFAULT.dup.tap do |options|
            options[:tags] = options[:tags].dup

            env = Datadog.configuration.env
            options[:tags] << "#{Environment::Ext::TAG_ENV}:#{env}" unless env.nil?

            version = Datadog.configuration.version
            options[:tags] << "#{Environment::Ext::TAG_VERSION}:#{version}" unless version.nil?
          end
        end
      end
    end
  end
end
