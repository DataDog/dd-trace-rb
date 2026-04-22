# frozen_string_literal: true

require 'json'

module Datadog
  module SymbolDatabase
    # Represents a scope in the hierarchical symbol structure (FILE → MODULE/CLASS → METHOD).
    #
    # Scopes form a tree structure representing Ruby code organization. Each scope contains:
    # - Metadata: name, source file, line range, scope type (MODULE/CLASS/METHOD/etc.)
    # - Symbols: Variables, constants, parameters defined in this scope
    # - Nested scopes: Child scopes (e.g., methods within a class)
    #
    # Created by: Extractor (during symbol extraction)
    # Used by: ScopeContext (batching), ServiceVersion (wrapping for upload)
    # Serialized to: JSON via to_h/to_json for upload to agent
    #
    # @api private
    class Scope
      attr_reader :scope_type, :name, :source_file, :start_line, :end_line,
        :has_injectible_lines, :injectible_lines,
        :language_specifics, :symbols, :scopes

      # Initialize a new Scope
      # @param scope_type [String] Type of scope (FILE, MODULE, CLASS, METHOD)
      # @param name [String, nil] Name of the scope (class name, method name, etc.)
      # @param source_file [String, nil] Path to source file
      # @param start_line [Integer, nil] Starting line number (UNKNOWN_MIN_LINE for unknown)
      # @param end_line [Integer, nil] Ending line number (UNKNOWN_MAX_LINE for entire file)
      # @param has_injectible_lines [Boolean] Whether injectable lines data is present
      # @param injectible_lines [Array<Hash>, nil] Ranges of executable lines [{start:, end:}]
      # @param language_specifics [Hash, nil] Ruby-specific metadata
      # @param symbols [Array<Symbol>, nil] Symbols defined in this scope
      # @param scopes [Array<Scope>, nil] Nested child scopes
      def initialize(
        scope_type:,
        name: nil,
        source_file: nil,
        start_line: nil,
        end_line: nil,
        has_injectible_lines: false,
        injectible_lines: nil,
        language_specifics: nil,
        symbols: nil,
        scopes: nil
      )
        @scope_type = scope_type
        @name = name
        @source_file = source_file
        @start_line = start_line
        @end_line = end_line
        @has_injectible_lines = has_injectible_lines
        @injectible_lines = injectible_lines
        @language_specifics = language_specifics || {}
        @symbols = symbols || []
        @scopes = scopes || []
      end

      # Convert scope to Hash for JSON serialization.
      # Removes nil values to reduce payload size.
      # @return [Hash] Scope as hash with symbol keys
      def to_h
        h = {
          scope_type: scope_type,
          name: name,
          source_file: source_file,
          start_line: start_line,
          end_line: end_line,
          language_specifics: language_specifics.empty? ? nil : language_specifics,
          symbols: symbols.empty? ? nil : symbols.map(&:to_h),
          scopes: scopes.empty? ? nil : scopes.map(&:to_h),
        }
        h.compact!
        # Injectable lines only on METHOD scopes (per spec — not on CLASS/MODULE/FILE).
        # Always emit has_injectible_lines (even when false) on METHOD scopes.
        if scope_type == 'METHOD'
          h[:has_injectible_lines] = has_injectible_lines # steep:ignore ArgumentTypeMismatch
          h[:injectible_lines] = injectible_lines if injectible_lines && !injectible_lines.empty?
        end
        h
      end

      # Serialize scope to JSON.
      # @return [String] JSON string representation
      def to_json(_state = nil)
        JSON.generate(to_h)
      end
    end
  end
end
