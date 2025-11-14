# frozen_string_literal: true

require_relative 'ext'

module Datadog
  module OpenFeature
    # This class is based on the `OpenFeature::SDK::Provider::ResolutionDetails` class
    #
    # See: https://github.com/open-feature/ruby-sdk/blob/v0.4.1/lib/open_feature/sdk/provider/resolution_details.rb
    class ResolutionDetails < Struct.new(
      :value,
      :reason,
      :variant,
      :error_code,
      :error_message,
      :flag_metadata,
      :allocation_key,
      :extra_logging,
      :log?,
      :error?,
      keyword_init: true
    )
      def self.build_success(value:, variant:, allocation_key:, do_log:, reason:)
        new(
          value: value,
          variant: variant,
          error_code: nil,
          error_message: nil,
          reason: reason,
          allocation_key: allocation_key,
          log?: do_log,
          error?: false,
          flag_metadata: {
            'allocationKey' => allocation_key,
            'doLog' => do_log
          },
          extra_logging: {}
        ).freeze
      end

      def self.build_default(value:, reason:)
        new(
          value: value,
          variant: nil,
          error_code: nil,
          error_message: nil,
          reason: reason,
          allocation_key: nil,
          log?: false,
          error?: false,
          flag_metadata: {},
          extra_logging: {}
        ).freeze
      end

      def self.build_error(value:, error_code:, error_message:, reason: Ext::ERROR)
        new(
          value: value,
          variant: nil,
          error_code: error_code,
          error_message: error_message,
          reason: reason,
          allocation_key: nil,
          log?: false,
          error?: true,
          flag_metadata: {},
          extra_logging: {}
        ).freeze
      end
    end
  end
end
