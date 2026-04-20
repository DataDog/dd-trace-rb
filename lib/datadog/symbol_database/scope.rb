# frozen_string_literal: true

require 'json'

module Datadog
  module SymbolDatabase
    # Represents a scope in the hierarchical symbol structure (MODULE -> CLASS -> METHOD).
    #
    # DESIGN VERIFICATION: Hierarchy description is INCOMPLETE.
    #   Source: design/scope-hierarchy.md, "Ruby (our implementation)" section
    #     Actual hierarchy: FILE -> MODULE/CLASS -> METHOD
    #     FILE is the root scope type (added via backend PR #1989)
    #   Source: specs/json-schema.md, "Root Scope Types" table (lines 120-127)
    #     Ruby root scope type is FILE
    #   The comment omits FILE as root. Should be: FILE -> MODULE/CLASS -> METHOD
    #
    # Scopes form a tree structure representing Ruby code organization. Each scope contains:
    # - Metadata: name, source file, line range, scope type (MODULE/CLASS/METHOD/etc.)
    # - Symbols: Variables, constants, parameters defined in this scope
    # - Nested scopes: Child scopes (e.g., methods within a class)
    #
    # DESIGN VERIFICATION:
    #   Source: design/symbol-extraction.md, "Data Models" (~line 488-522)
    #     Scope class with these attr_readers -- ACCURATE
    #   Source: specs/json-schema.md, "Scope Object" section
    #     Fields: scope_type, name, source_file, start_line, end_line,
    #     language_specifics, symbols, scopes -- ACCURATE
    #
    # Created by: Extractor (during symbol extraction)
    # Used by: ScopeContext (batching), ServiceVersion (wrapping for upload)
    # Serialized to: JSON via to_h/to_json for upload to agent
    #
    # DESIGN VERIFICATION:
    #   Source: design/ruby-architecture.md
    #     Pipeline: Extractor -> ScopeContext -> Uploader -- ACCURATE
    #   Source: design/json-serialization.md, lines 16-18
    #     Each class has to_h and to_json methods -- ACCURATE
    #
    # @api private
    class Scope
      attr_reader :scope_type, :name, :source_file, :start_line, :end_line,
        :has_injectible_lines, :injectible_lines,
        :language_specifics, :symbols, :scopes

      # Initialize a new Scope
      # @param scope_type [String] Type of scope (MODULE, CLASS, METHOD, LOCAL, CLOSURE)
      #
      # DESIGN VERIFICATION: scope_type @param list is INACCURATE for Ruby.
      #   Source: specs/json-schema.md, lines 110-114
      #     Ruby scope types: FILE, MODULE, CLASS, METHOD
      #     LOCAL and CLOSURE are NOT Ruby scope types (they belong to Java/.NET/Go)
      #   Source: design/scope-hierarchy.md, "Ruby Language Entities" table
      #     Block/Proc/Lambda -> Skip (no CLOSURE). LOCAL scopes -> deferred.
      #   Should list: FILE, MODULE, CLASS, METHOD
      #
      # @param name [String, nil] Name of the scope (class name, method name, etc.)
      # @param source_file [String, nil] Path to source file
      # @param start_line [Integer, nil] Starting line number (UNKNOWN_MIN_LINE for unknown)
      # @param end_line [Integer, nil] Ending line number (UNKNOWN_MAX_LINE for entire file)
      # @param has_injectible_lines [Boolean] Whether injectable lines data is present
      # @param injectible_lines [Array<Hash>, nil] Ranges of executable lines [{start:, end:}]
      # @param language_specifics [Hash, nil] Ruby-specific metadata
      # @param symbols [Array<Symbol>, nil] Symbols defined in this scope
      # @param scopes [Array<Scope>, nil] Nested child scopes
      #
      # DESIGN VERIFICATION (remaining @params):
      #   name: specs/json-schema.md line 70 -- must be FQN for CLASS/MODULE,
      #     bare for METHOD, absolute path for FILE. No validation here, which is
      #     correct per design/json-serialization.md "Minimal validation". ACCURATE.
      #   source_file: specs/json-schema.md line 71 -- absolute runtime paths. ACCURATE.
      #   start_line/end_line: specs/json-schema.md lines 72-73 -- 0 and 2147483647
      #     as sentinels. ACCURATE.
      #   has_injectible_lines: specs/json-schema.md line 74 -- always emitted on
      #     METHOD scopes. ACCURATE.
      #   injectible_lines: specs/json-schema.md line 75 -- ranges of executable
      #     lines, each {start, end}. ACCURATE.
      #   language_specifics: specs/json-schema.md lines 177-255 -- FILE: {file_hash},
      #     CLASS: {super_classes, included_modules, prepended_modules},
      #     METHOD: {visibility, method_type}. ACCURATE.
      #   symbols/scopes: recursive nesting. ACCURATE.
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
        # DESIGN VERIFICATION: default {} matches
        #   design/symbol-extraction.md line ~505. ACCURATE.
        @symbols = symbols || []
        @scopes = scopes || []
      end

      # Convert scope to Hash for JSON serialization.
      # Removes nil values to reduce payload size.
      # @return [Hash] Scope as hash with symbol keys
      #
      # DESIGN VERIFICATION:
      #   Source: design/json-serialization.md, lines 40-64
      #     Uses .compact to remove nil values -- ACCURATE
      #     Don't include empty arrays/hashes -- ACCURATE
      #   Source: specs/json-schema.md, "Optional Fields Policy"
      #     Omit nil, empty arrays, empty objects -- ACCURATE
      def to_h
        h = {
          scope_type: scope_type,
          name: name,
          source_file: source_file,
          start_line: start_line,
          end_line: end_line,
          language_specifics: language_specifics.empty? ? nil : language_specifics,
          # DESIGN VERIFICATION: Empty language_specifics mapped to nil then compacted.
          #   design/json-serialization.md line 57-60: "Don't include empty hashes" -- ACCURATE
          #   Note: The design doc's example code (line 50-53) does NOT do this check;
          #   the implementation is MORE correct than the design doc's example.
          symbols: symbols.empty? ? nil : symbols.map(&:to_h),
          scopes: scopes.empty? ? nil : scopes.map(&:to_h),
        }.compact
        # Injectable lines only on METHOD scopes (per spec -- not on CLASS/MODULE/FILE).
        # Always emit has_injectible_lines (even when false) on METHOD scopes.
        #
        # DESIGN VERIFICATION:
        #   Source: specs/json-schema.md, line 74
        #     "Always emitted on METHOD scopes. Not present on CLASS, FILE, MODULE" -- ACCURATE
        #   Source: design/symbol-extraction.md, "Injectable Lines" > "Serialization"
        #     "Always emit has_injectible_lines on METHOD scopes.
        #      Emit injectible_lines only when non-empty." -- ACCURATE
        if scope_type == 'METHOD'
          h[:has_injectible_lines] = has_injectible_lines # steep:ignore ArgumentTypeMismatch
          h[:injectible_lines] = injectible_lines if injectible_lines && !injectible_lines.empty?
        end
        h
      end

      # Serialize scope to JSON.
      # @return [String] JSON string representation
      #
      # DESIGN VERIFICATION:
      #   Source: design/json-serialization.md, lines 30-36, 68-71
      #     JSON.generate(to_h), compact format -- ACCURATE
      def to_json(_state = nil)
        JSON.generate(to_h)
      end
    end
  end
end
