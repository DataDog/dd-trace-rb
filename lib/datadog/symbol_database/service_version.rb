# frozen_string_literal: true

require 'json'

module Datadog
  module SymbolDatabase
    # Top-level container wrapping scopes for upload to the agent.
    #
    # ServiceVersion is the root object serialized to JSON for symbol database uploads.
    # Contains service metadata (name, env, version) and all extracted scopes.
    # The language field identifies the tracer.
    #
    # Created by: Uploader (wraps scopes array before serialization)
    # Contains: Array of top-level Scope objects (MODULE scopes)
    #
    # DESIGN VERIFICATION: "MODULE scopes" is INACCURATE.
    #   Source: specs/json-schema.md, "Root Scope Types" table (lines 120-127)
    #     Ruby root scope type is FILE, not MODULE
    #   Source: design/scope-hierarchy.md, "Root Scope Choice: FILE"
    #     "Ruby uses FILE as the root scope -- one FILE scope per source file"
    #   Should say: "Array of top-level Scope objects (FILE scopes)"
    #
    # Serialized to: JSON via to_json, then GZIP compressed for upload
    #
    # DESIGN VERIFICATION:
    #   Source: design/json-serialization.md, lines 83-105
    #     ServiceVersion wraps scopes with service, env, version, language -- ACCURATE
    #   Source: specs/json-schema.md, "Top-Level: ServiceVersion" (lines 15-37)
    #     Fields: service, env, version, language, scopes (all required) -- ACCURATE
    #     schema_version optional, Python-only (line 36, 749-751) -- correctly omitted
    #
    # @api private
    class ServiceVersion
      attr_reader :service, :env, :version, :language, :scopes

      # Initialize a new ServiceVersion
      # @param service [String] Service name (required, from DD_SERVICE)
      # @param env [String] Environment (from DD_ENV, defaults to "none")
      # @param version [String] Version (from DD_VERSION, defaults to "none")
      # @param scopes [Array<Scope>] Top-level scopes (required)
      # @raise [ArgumentError] if service empty or scopes not an array
      #
      # DESIGN VERIFICATION:
      #   Source: design/json-serialization.md, lines 177-191
      #     Validation: service required, scopes must be array -- ACCURATE
      #     env defaults to 'none' when empty -- ACCURATE
      #     version defaults to 'none' when empty -- ACCURATE
      #   Note: design doc (line 181-182) only checks nil, not empty string.
      #     Implementation here handles both nil and empty via .to_s.empty? --
      #     this is MORE thorough than the design doc's example. ACCURATE+.
      def initialize(service:, env:, version:, scopes:)
        raise ArgumentError, 'service is required' if service.nil? || service.empty?
        raise ArgumentError, 'scopes must be an array' unless scopes.is_a?(Array)

        @service = service
        @env = env.to_s.empty? ? 'none' : env.to_s
        @version = version.to_s.empty? ? 'none' : version.to_s
        @language = 'ruby'
        # DESIGN VERIFICATION:
        #   Source: specs/json-schema.md, line 42
        #     Ruby language value: "ruby" (lowercase) -- ACCURATE
        #   Source: specs/json-schema.md, lines 709-719
        #     "Convention is lowercase -- Ruby should send 'ruby'" -- ACCURATE
        #   CAVEAT: design/json-serialization.md line 107 says
        #     'Language field: Always "ruby" (uppercase, from spec)'
        #     The parenthetical "(uppercase, from spec)" is INACCURATE in the
        #     design doc -- the value "ruby" is lowercase and the spec confirms
        #     lowercase. The implementation is correct; the design doc text is wrong.
        @scopes = scopes
      end

      # Convert service version to Hash for JSON serialization.
      # @return [Hash] ServiceVersion as hash with symbol keys
      #
      # DESIGN VERIFICATION:
      #   Source: design/json-serialization.md, lines 83-105
      #     Hash: service, env, version, language, scopes -- ACCURATE
      #   Source: specs/json-schema.md, "Top-Level: ServiceVersion"
      #     JSON structure matches -- ACCURATE
      #   Note: No .compact (unlike Scope.to_h). Correct because all fields are
      #     always present (env/version default to "none"). ACCURATE.
      #   Note: schema_version NOT emitted. Correct per specs/json-schema.md
      #     line 749-751: "schema_version is Python-only". ACCURATE.
      def to_h
        {
          service: service,
          env: env,
          version: version,
          language: language,
          scopes: scopes.map(&:to_h),
        }
      end

      # Serialize service version to JSON.
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
