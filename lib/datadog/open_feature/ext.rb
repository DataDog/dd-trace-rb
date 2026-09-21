# frozen_string_literal: true

module Datadog
  module OpenFeature
    module Ext
      ERROR = "ERROR"
      DEFAULT = "DEFAULT"
      INITIALIZING = "INITIALIZING"
      UNKNOWN_TYPE = "UNKNOWN_TYPE"
      PARSE_ERROR = "PARSE_ERROR"
      GENERAL = "GENERAL"
      PROVIDER_FATAL = "PROVIDER_FATAL"
      PROVIDER_NOT_READY = "PROVIDER_NOT_READY"
      FLAG_NOT_FOUND = "FLAG_NOT_FOUND"
      TYPE_MISMATCH = "TYPE_MISMATCH"
      TARGETING_KEY_MISSING = "TARGETING_KEY_MISSING"
      INVALID_CONTEXT = "INVALID_CONTEXT"

      STANDARD_ERROR_CODES = [
        PROVIDER_NOT_READY,
        FLAG_NOT_FOUND,
        PARSE_ERROR,
        TYPE_MISMATCH,
        TARGETING_KEY_MISSING,
        INVALID_CONTEXT,
        PROVIDER_FATAL,
        GENERAL,
      ].freeze

      # Flag-metadata key under which the provider threads the assignment's
      # allocation key to the flag-evaluation hooks. The wire string is the
      # value so the writer (provider) and readers (EVP/metrics hooks) can't drift.
      METADATA_ALLOCATION_KEY = "__dd_allocation_key"

      # Stamped from the UFC the evaluation ran against; the hook reads only this
      # key, never live config.
      METADATA_OBSERVE_FULL_EVALUATION_DATA = "__dd_observe_full_evaluation_data"
    end
  end
end
