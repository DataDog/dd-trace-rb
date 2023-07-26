# frozen_string_literal: true

require_relative '../ext/settings'

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
                o.type :bool
                o.env CI::Ext::Settings::ENV_MODE_ENABLED
                o.default false
              end

              # DEV: Alias to Datadog::Tracing::Contrib::Extensions::Configuration::Settings#instrument.
              # DEV: Should be removed when CI implement its own `c.ci.instrument`.
              define_method(:instrument) do |integration_name, options = {}, &block|
                Datadog.configuration.tracing.instrument(integration_name, options, &block)
              end

              # DEV: Alias to Datadog::Tracing::Contrib::Extensions::Configuration::Settings#instrument.
              # DEV: Should be removed when CI implement its own `c.ci[]`.
              define_method(:[]) do |integration_name, key = :default|
                Datadog.configuration.tracing[integration_name, key]
              end

              # TODO: Deprecate in the next major version, as `instrument` better describes this method's purpose
              alias_method :use, :instrument

              option :trace_flush

              option :writer_options do |o|
                o.type :hash
                o.default({})
              end
            end
          end
        end
      end
    end
  end
end
