# frozen_string_literal: true

module Datadog
  module OpenFeature
    module Configuration
      # A settings class for the OpenFeature component.
      module Settings
        def self.extended(base)
          base = base.singleton_class unless base.is_a?(Class)
          add_settings!(base)
        end

        def self.add_settings!(base)
          base.class_eval do
            settings :open_feature do
              option :enabled do |o|
                o.type :bool
                o.env 'DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED'
                o.default false
              end
            end
          end
        end
      end
    end
  end
end
