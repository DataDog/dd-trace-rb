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
            # Steep does not update `self` for this `class_eval` block.
            # @type self: Datadog::Core::Configuration::Base::_DslContext
            settings :open_feature do
              option :enabled do |o|
                o.type :bool
                o.env 'DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED'
                o.default false
              end

              # Opt-in gate for APM feature-flag span enrichment. When enabled,
              # the provider attaches `ffe_*` tags to the local root APM span on
              # finish. Distinct from `:enabled` (the provider gate) and off by
              # default so it can be rolled out independently.
              option :span_enrichment_enabled do |o|
                o.type :bool
                o.env 'DD_EXPERIMENTAL_FLAGGING_PROVIDER_SPAN_ENRICHMENT_ENABLED'
                o.default false
              end

              # Killswitch for the EVP `flagevaluation` emission path only. Default on; when
              # disabled the existing OTel `feature_flag.evaluations` metric is unaffected.
              option :evaluation_counts_enabled do |o|
                o.type :bool
                o.env 'DD_FLAGGING_EVALUATION_COUNTS_ENABLED'
                o.default true
              end
            end
          end
        end
      end
    end
  end
end
