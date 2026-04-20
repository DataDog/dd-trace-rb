# frozen_string_literal: true

require 'json'

require_relative 'symbol'

module Datadog
  module SymbolDatabase
    # Represents a scope in the hierarchical symbol structure.
    #
    # @api private
    class Scope
      attr_reader \
        :scope_type,
        :name,
        :source_file,
        :start_line,
        :end_line,
        :has_injectible_lines,
        :injectible_lines,
        :language_specifics,
        :symbols,
        :scopes

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

      def to_h
        hash = {
          scope_type: scope_type,
          name: name,
          source_file: source_file,
          start_line: start_line,
          end_line: end_line,
          language_specifics: language_specifics.empty? ? nil : language_specifics,
          symbols: symbols.empty? ? nil : symbols.map(&:to_h),
          scopes: scopes.empty? ? nil : scopes.map(&:to_h),
        }.compact

        if scope_type == 'METHOD'
          hash[:has_injectible_lines] = has_injectible_lines # steep:ignore ArgumentTypeMismatch
          hash[:injectible_lines] = injectible_lines if injectible_lines && !injectible_lines.empty?
        end

        hash
      end

      def to_json(_state = nil)
        JSON.generate(to_h)
      end
    end
  end
end
