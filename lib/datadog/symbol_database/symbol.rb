# frozen_string_literal: true

require 'json'

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
    # DESIGN VERIFICATION:
    #   Source: specs/json-schema.md, "SymbolType Enum" (lines 164-169)
    #     FIELD = "Instance variable/field (@var in Ruby)" -- ACCURATE
    #     STATIC_FIELD = "Class variable/constant (@@var or CONSTANT)" -- ACCURATE
    #     ARG = "Method/function argument" -- ACCURATE
    #     LOCAL = "Local variable" -- ACCURATE (deferred, not yet implemented)
    #   Source: design/symbol-extraction.md, lines 275-333
    #     Class variables -> STATIC_FIELD, Constants -> STATIC_FIELD,
    #     Parameters -> ARG -- ACCURATE
    #   Note: "Instance variables (@var) - FIELD type" is accurate about the TYPE
    #     MAPPING but potentially misleading: per requirements.md "What Is Not In
    #     Scope", instance variable extraction is deferred. Ruby does NOT currently
    #     emit FIELD symbols. The mapping is correct; the feature is not implemented.
    #
    # Created by: Extractor (during class/method introspection)
    # Contained in: Scope objects (symbols array)
    # Serialized to: JSON via to_h/to_json
    #
    # DESIGN VERIFICATION:
    #   Source: design/symbol-extraction.md, "Data Models" (~line 524-545)
    #     Symbol class with attr_readers -- ACCURATE
    #   Source: design/json-serialization.md, lines 16-18
    #     to_h and to_json methods -- ACCURATE
    #
    # @api private
    class Symbol
      attr_reader :symbol_type, :name, :line, :type, :language_specifics

      # Initialize a new Symbol
      # @param symbol_type [String] Type: FIELD, STATIC_FIELD, ARG, LOCAL
      #
      # DESIGN VERIFICATION:
      #   Source: specs/json-schema.md, lines 163-169
      #     "All languages use the same enum: FIELD, STATIC_FIELD, ARG, LOCAL" -- ACCURATE
      #   Source: design/symbol-extraction.md
      #     Ruby currently emits: STATIC_FIELD (class vars, constants), ARG (params)
      #     Deferred: FIELD (instance vars), LOCAL (local vars) -- ACCURATE
      #
      # @param name [String] Symbol name (variable name, parameter name)
      #
      # DESIGN VERIFICATION:
      #   Source: specs/json-schema.md, line 157
      #     "name: string, Yes" -- required field -- ACCURATE
      #
      # @param line [Integer] Line number (UNKNOWN_MIN_LINE for entire scope, UNKNOWN_MAX_LINE for method-level only)
      #
      # DESIGN VERIFICATION:
      #   Source: specs/json-schema.md, line 158
      #     "line: integer, Yes, Line where symbol is defined (0 = entire scope)" -- ACCURATE
      #   Source: specs/json-schema.md, "Special Line Number Values" table
      #     0 = available from start; 2147483647 = avoid line probe completion -- ACCURATE
      #
      # @param type [String, nil] Type annotation (optional, Ruby is dynamic)
      #
      # DESIGN VERIFICATION:
      #   Source: specs/json-schema.md, line 159
      #     "type: string, No, Type annotation" -- optional -- ACCURATE
      #   Source: design/symbol-extraction.md, line 285
      #     "Ruby doesn't have static types" -- type is nil for most symbols -- ACCURATE
      #
      # @param language_specifics [Hash, nil] Symbol-specific metadata
      #
      # DESIGN VERIFICATION:
      #   Source: specs/json-schema.md, line 160
      #     "language_specifics: object, No" -- optional -- ACCURATE
      #   Note: No Ruby-specific symbol language_specifics are defined in the spec.
      #     Field exists for forward compatibility. ACCURATE.
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
        # DESIGN VERIFICATION:
        #   Source: design/symbol-extraction.md, lines 526-534
        #     Symbol stores: symbol_type, name, line, type, language_specifics -- ACCURATE
        #   Note: Unlike Scope, language_specifics defaults to nil (not {}).
        #     Consistent with design/symbol-extraction.md line 534. ACCURATE.
      end

      # Convert symbol to Hash for JSON serialization.
      # Removes nil values to reduce payload size.
      # @return [Hash] Symbol as hash with symbol keys
      #
      # DESIGN VERIFICATION:
      #   Source: design/symbol-extraction.md, lines 536-543
      #     to_h with .compact to remove nils -- ACCURATE
      #   Source: design/json-serialization.md, "Optional Fields Policy"
      #     "Omit fields with no meaningful value" -- ACCURATE
      def to_h
        {
          symbol_type: symbol_type,
          name: name,
          line: line,
          type: type,
          language_specifics: language_specifics,
        }.compact
      end

      # Serialize symbol to JSON.
      # @return [String] JSON string representation
      #
      # DESIGN VERIFICATION:
      #   Source: design/json-serialization.md, lines 30-36
      #     JSON.generate(to_h) -- ACCURATE
      def to_json(_state = nil)
        JSON.generate(to_h)
      end
    end
  end
end
