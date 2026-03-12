# frozen_string_literal: true

require 'json'

module Datadog
  module SymbolDatabase
    # Represents a scope in the hierarchical symbol structure (MODULE → CLASS → METHOD).
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
        :language_specifics, :symbols, :scopes

      # Initialize a new Scope
      # @param scope_type [String] Type of scope (MODULE, CLASS, METHOD, LOCAL, CLOSURE)
      # @param name [String, nil] Name of the scope (class name, method name, etc.)
      # @param source_file [String, nil] Path to source file
      # @param start_line [Integer, nil] Starting line number (UNKNOWN_MIN_LINE for unknown)
      # @param end_line [Integer, nil] Ending line number (UNKNOWN_MAX_LINE for entire file)
      # @param language_specifics [Hash, nil] Ruby-specific metadata
      # @param symbols [Array<Symbol>, nil] Symbols defined in this scope
      # @param scopes [Array<Scope>, nil] Nested child scopes
      def initialize(
        scope_type:,
        name: nil,
        source_file: nil,
        start_line: nil,
        end_line: nil,
        language_specifics: nil,
        symbols: nil,
        scopes: nil
      )
        @scope_type = scope_type
        @name = name
        @source_file = source_file
        @start_line = start_line
        @end_line = end_line
        @language_specifics = language_specifics || {}
        @symbols = symbols || []
        @scopes = scopes || []
      end

      # Convert scope to Hash for JSON serialization.
      # Removes nil values to reduce payload size.
      # @return [Hash] Scope as hash with symbol keys
      def to_h
        {
          scope_type: scope_type,
          name: name,
          source_file: source_file,
          start_line: start_line,
          end_line: end_line,
          language_specifics: language_specifics.empty? ? nil : language_specifics,
          symbols: symbols.empty? ? nil : symbols.map(&:to_h),
          scopes: scopes.empty? ? nil : scopes.map(&:to_h)
        }.compact
      end

      # Serialize scope to JSON.
      # @return [String] JSON string representation
      def to_json(*)
        JSON.generate(to_h)
      end
    end
  end
end
