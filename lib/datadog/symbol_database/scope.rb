# frozen_string_literal: true

module Datadog
  module SymbolDatabase
    # Represents a lexical scope in the symbol database hierarchy.
    # Scopes form a tree: MODULE -> CLASS -> METHOD -> LOCAL/CLOSURE
    class Scope
      attr_accessor :scope_type, :name, :source_file, :start_line, :end_line,
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
        @language_specifics = language_specifics
        @symbols = symbols
        @scopes = scopes
      end

      def to_h
        h = { scope_type: @scope_type }
        h[:name] = @name if @name
        h[:source_file] = @source_file if @source_file
        h[:start_line] = @start_line if @start_line
        h[:end_line] = @end_line if @end_line
        h[:language_specifics] = @language_specifics if @language_specifics && !@language_specifics.empty?
        h[:symbols] = @symbols.map(&:to_h) if @symbols && !@symbols.empty?
        h[:scopes] = @scopes.map(&:to_h) if @scopes && !@scopes.empty?
        h
      end
    end
  end
end
