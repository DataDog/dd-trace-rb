# frozen_string_literal: true

module Datadog
  module OpenFeature
    module Binding
      # Assignment reasons returned in ResolutionDetails
      module AssignmentReason
        TARGETING_MATCH = 'TARGETING_MATCH'
        SPLIT = 'SPLIT'
        STATIC = 'STATIC'
        DEFAULT = 'DEFAULT'
        DISABLED = 'DISABLED'
        ERROR = 'ERROR'
      end
    end
  end
end
