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
            settings :ci_mode do
              option :enabled do |o|
                o.default { env_to_bool(Datadog::CI::Ext::Settings::ENV_MODE_ENABLED, false) }
                o.lazy
              end

              option :context_flush do |o|
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
