# frozen_string_literal: true

module Datadog
  # Namespace for Datadog symbol database upload.
  #
  # @api private
  module SymbolDatabase
    # Sentinel value for unknown or unavailable minimum line number.
    #
    # Backend behavior: line=0 means symbol completes in every line of the scope.
    UNKNOWN_MIN_LINE = 0

    # Sentinel value for unknown or unavailable maximum line number.
    #
    # Backend behavior: 2147483647 means "unknown maximum" / "whole remaining scope".
    UNKNOWN_MAX_LINE = 2147483647
  end
end
