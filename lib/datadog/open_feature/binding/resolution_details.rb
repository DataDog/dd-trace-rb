# frozen_string_literal: true

module Datadog
  module OpenFeature
    # A namespace for binding code
    module Binding
      ResolutionDetails = Struct.new(
        :value,
        :reason,
        :variant,
        :error_code,
        :error_message,
        :flag_metadata,
        :allocation_key,
        :do_log,
        :extra_logging,
        keyword_init: true
      )
    end
  end
end
