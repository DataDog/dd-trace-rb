# frozen_string_literal: true

module Datadog
  module OpenFeature
    module Binding
      # Assignment reasons returned in ResolutionDetails
      # Aligned with libdatadog FFI Reason enum
      module AssignmentReason
        TARGETING_MATCH = 'TARGETING_MATCH'
        SPLIT = 'SPLIT'
        STATIC = 'STATIC'
        DEFAULT = 'DEFAULT'      # For DefaultAllocationNull cases (matches libdatadog FFI Reason::Default)
        DISABLED = 'DISABLED'    # For FlagDisabled cases  
        ERROR = 'ERROR'
      end
    end
  end
end
