# typed: false

require 'datadog/ci/ext/settings'

module Datadog
  module CI
    module Configuration
      # Adds CI behavior to Datadog trace settings
      module Settings
        def self.extended(base)
          base = base.singleton_class unless base.is_a?(Class)
          add_settings!(base)
        end

        def self.add_settings!(base)
          base.class_eval do
            settings :ci do
              option :enabled do |o|
                o.default { env_to_bool(CI::Ext::Settings::ENV_MODE_ENABLED, false) }
                o.lazy
              end

              # DEV: Alias to Datadog::Tracing::Contrib::Extensions::Configuration::Settings#instrument.
              # DEV: Should be removed when `c.ci.instrument` namespacing is complete.
              define_method(:instrument) do |integration_name, options = {}, &block|
                Datadog.configuration.send(:instrument, integration_name, options, &block)
              end

              # TODO: Deprecate in the next major version, as `instrument` better describes this method's purpose
              alias_method :use, :instrument

              option :trace_flush do |o|
                o.default { nil }
                o.lazy
              end

              option :writer_options do |o|
                o.default { {} }
                o.lazy
              end
            end
          end
        end
      end
    end
  end
end
