# frozen_string_literal: true

module Datadog
  module Debugger
    module Configuration
      # Settings
      module Settings

        def self.extended(base)
          base = base.singleton_class unless base.is_a?(Class)
          add_settings!(base)
        end

        # rubocop:disable Metrics/AbcSize,Metrics/MethodLength,Metrics/BlockLength,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
        def self.add_settings!(base)
          base.class_eval do
            settings :debugger do
              option :enabled do |o|
                o.type :bool
                o.env 'DD_DYNAMIC_INSTRUMENTATION_ENABLED'
                o.default false
              end

            end
          end
        end
      end
    end
  end
end
