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

      # Flag-metadata key under which the provider threads the assignment's
      # allocation key to the flag-evaluation hooks. The wire string is the
      # value so the writer (provider) and readers (EVP/metrics hooks) can't drift.
      METADATA_ALLOCATION_KEY = "__dd_allocation_key"
    end
  end
end
