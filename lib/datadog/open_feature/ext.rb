# frozen_string_literal: true

module Datadog
  module OpenFeature
    module Ext
      # OpenFeature error codes  
      ERROR = 'ERROR'
      INITIALIZING = 'INITIALIZING'
      UNKNOWN_TYPE = 'UNKNOWN_TYPE'
      PROVIDER_FATAL = 'PROVIDER_FATAL'
      PROVIDER_NOT_READY = 'PROVIDER_NOT_READY'
      TYPE_MISMATCH = 'TYPE_MISMATCH'
      PARSE_ERROR = 'PARSE_ERROR'
      FLAG_NOT_FOUND = 'FLAG_NOT_FOUND'
      
      # Rust EvaluationError enum values (internal error codes)
      TYPE_MISMATCH_ERROR = 'TypeMismatch'
      CONFIGURATION_PARSE_ERROR = 'ConfigurationParseError'
      CONFIGURATION_MISSING = 'ConfigurationMissing'
      FLAG_UNRECOGNIZED_OR_DISABLED = 'FlagUnrecognizedOrDisabled'
      FLAG_DISABLED = 'FlagDisabled'
      DEFAULT_ALLOCATION_NULL = 'DefaultAllocationNull'
      INTERNAL_ERROR = 'Internal'
    end
  end
end
