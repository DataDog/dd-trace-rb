# frozen_string_literal: true

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
    class Scope
      attr_reader :scope_type, :name, :source_file, :start_line, :end_line,
        :language_specifics, :symbols, :scopes

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

      # Convert scope to Hash for JSON serialization
      # Removes nil values to reduce payload size
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

      # Serialize scope to JSON
      def to_json(*args)
        require 'json'
        JSON.generate(to_h, *args)
      end
    end
  end
end
