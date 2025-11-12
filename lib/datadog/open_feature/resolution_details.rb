# frozen_string_literal: true

module Datadog
  module OpenFeature
    # The result of the evaluation
    ResolutionDetails = Struct.new(
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
  end
end
