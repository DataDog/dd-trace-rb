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
      def self.build_error(value:, error_code:, error_message:, reason: Ext::ERROR)
        new(
          value: value,
          error_code: error_code,
          error_message: error_message,
          reason: reason,
          error?: true,
          log?: false
        ).freeze
      end
    end
  end
end
