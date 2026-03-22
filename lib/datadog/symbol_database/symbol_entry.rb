# frozen_string_literal: true

module Datadog
  module SymbolDatabase
    # Represents a symbol (variable, field, parameter) within a scope.
    # Named SymbolEntry to avoid conflict with Ruby's Symbol class.
    class SymbolEntry
      attr_accessor :symbol_type, :name, :line, :type

      def initialize(symbol_type:, name:, line:, type: nil)
        @symbol_type = symbol_type
        @name = name
        @line = line
        @type = type
      end

      def to_h
        h = {
          symbol_type: @symbol_type,
          name: @name,
          line: @line,
        }
        h[:type] = @type if @type
        h
      end
    end
  end
end
