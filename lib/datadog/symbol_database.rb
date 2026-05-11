# frozen_string_literal: true

module Datadog
  # Namespace for Datadog symbol database upload.
  #
  # @api private
  module SymbolDatabase
    # Sentinel value for unknown or unavailable minimum line number.
    #
    # Used for:
    # 1. start_line when exact line cannot be determined (e.g., modules without methods)
    # 2. Symbol line numbers for FIELD, STATIC_FIELD, ARG symbols to indicate
    #    the symbol is available throughout the entire enclosing scope
    #
    # Backend behavior: line=0 means symbol completes in every line of the scope
    #
    # Reference: Symbol Database Backend RFC, section "Edge Cases"
    # - "We use 0 for FIELD, STATIC_FIELD and ARG. It means that the symbol
    #   will be completed in every line of the enclosing scope (CLASS or METHOD)."
    #
    # @see https://www.postgresql.org/docs/current/datatype-numeric.html
    UNKNOWN_MIN_LINE = 0

    # Sentinel value for unknown or unavailable maximum line number.
    #
    # Used for:
    # 1. end_line when exact boundaries cannot be determined (e.g., modules, classes
    #    without methods, fallback when introspection fails)
    # 2. LOCAL symbol line numbers when exact line is unknown (future feature)
    #
    # Value: 2147483647 (PostgreSQL signed INT_MAX, 2^31 - 1)
    #
    # Backend behavior:
    # - For scopes: indicates "entire file" or "unknown end"
    # - For LOCAL symbols (future): included in method probe completions but excluded
    #   from line probe completions
    #
    # Protocol specification:
    # - "If the symbols of the scope should be available to all lines in the
    #   source_file of the scope, use start_line = 0 and end_line = 2147483647
    #   (maximum signed integer, postgres int max)."
    # - "For LOCAL symbols, we use 2147483647 (signed int max) to avoid completing
    #   the symbol for line probes, but keep it in the method for method probe completions."
    #
    # Reference: Symbol Database Backend RFC, section "Scope" and "Edge Cases"
    # @see https://www.postgresql.org/docs/current/datatype-numeric.html
    UNKNOWN_MAX_LINE = 2147483647
  end
end
