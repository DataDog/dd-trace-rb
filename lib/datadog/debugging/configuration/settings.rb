# frozen_string_literal: true

module Datadog
  module Debugging
    module Configuration
      # Settings
      module Settings
        def self.extended(base)
          base = base.singleton_class unless base.is_a?(Class)
          add_settings!(base)
        end

        def self.add_settings!(base)
          base.class_eval do
            settings :debugging do
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
