# frozen_string_literal: true

module Datadog
  module OpenFeature
    module Ext
      PROVIDER_NAME = "Datadog Feature Flagging Provider"

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

      METADATA_DO_LOG = "__dd_do_log"
      METADATA_SPLIT_SERIAL_ID = "__dd_split_serial_id"
      METADATA_EXPOSURE_CACHE_HIT = "__dd_exposure_cache_hit"

      # Split features are flattened into metadata as one entry per destination.
      # `__dd_feature.` is the public prefix customers read; the others are internal.
      METADATA_FEATURE_PREFIX = "__dd_feature."
      METADATA_EXPOSURE_FEATURE_PREFIX = "__dd_exposure_feature."
      METADATA_EVALUATION_FEATURE_PREFIX = "__dd_evaluation_feature."
    end
  end
end
