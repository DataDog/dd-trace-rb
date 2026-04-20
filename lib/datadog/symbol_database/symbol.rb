# frozen_string_literal: true

require 'json'

require_relative '../symbol_database'

module Datadog
  module SymbolDatabase
    # Represents a symbol within a scope.
    #
    # @api private
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

      def to_h
        {
          symbol_type: symbol_type,
          name: name,
          line: line,
          type: type,
          language_specifics: language_specifics,
        }.compact
      end

      def to_json(_state = nil)
        JSON.generate(to_h)
      end
    end
  end
end
