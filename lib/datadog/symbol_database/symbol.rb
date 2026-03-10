# frozen_string_literal: true

module Datadog
  module SymbolDatabase
    # Represents a symbol (variable, parameter, field, constant) within a scope.
    #
    # Symbols are the actual identifiers extracted from Ruby code:
    # - Instance variables (@var) - FIELD type
    # - Class variables (@@var) - STATIC_FIELD type
    # - Constants (CONST) - STATIC_FIELD type
    # - Method parameters (arg) - ARG type
    # - Local variables (var) - LOCAL type (not yet implemented)
    #
    # Created by: Extractor (during class/method introspection)
    # Contained in: Scope objects (symbols array)
    # Serialized to: JSON via to_h/to_json
    #
    # @api private
    class Symbol
      attr_reader :symbol_type, :name, :line, :type, :language_specifics

      # Initialize a new Symbol
      # @param symbol_type [String] Type: FIELD, STATIC_FIELD, ARG, LOCAL
      # @param name [String] Symbol name (variable name, parameter name)
      # @param line [Integer] Line number (0 for entire scope, 2147483647 for method-level only)
      # @param type [String, nil] Type annotation (optional, Ruby is dynamic)
      # @param language_specifics [Hash, nil] Symbol-specific metadata
      def initialize(
        symbol_type:,
        name:,
        line:,
        type: nil,
        language_specifics: nil
      )
        @symbol_type = symbol_type
        @name = name
        @line = line
        @type = type
        @language_specifics = language_specifics
      end

      # Convert symbol to Hash for JSON serialization.
      # Removes nil values to reduce payload size.
      # @return [Hash] Symbol as hash with symbol keys
      def to_h
        {
          symbol_type: symbol_type,
          name: name,
          line: line,
          type: type,
          language_specifics: language_specifics
        }.compact
      end

      # Serialize symbol to JSON.
      # @param args [Array] Optional arguments for JSON.generate
      # @return [String] JSON string representation
      def to_json(*args)
        require 'json'
        JSON.generate(to_h, *args)
      end
    end
  end
end
