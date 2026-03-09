# frozen_string_literal: true

module Datadog
  module SymbolDatabase
    # Represents a symbol (variable, parameter, field, etc.)
    class Symbol
      attr_reader :symbol_type, :name, :line, :type, :language_specifics

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

      # Convert symbol to Hash for JSON serialization
      # Removes nil values to reduce payload size
      def to_h
        {
          symbol_type: symbol_type,
          name: name,
          line: line,
          type: type,
          language_specifics: language_specifics
        }.compact
      end

      # Serialize symbol to JSON
      def to_json(*args)
        require 'json'
        JSON.generate(to_h, *args)
      end
    end
  end
end
