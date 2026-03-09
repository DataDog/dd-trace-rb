# frozen_string_literal: true

module Datadog
  module SymbolDatabase
    # Represents a scope in the symbol hierarchy (MODULE, CLASS, METHOD, etc.)
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
