# frozen_string_literal: true

# TODO: Revert language to 'RUBY' and ddsource to 'ruby' (in uploader.rb) after
# DataDog/debugger-backend#1974 merges. That PR adds RUBY to the backend storage
# Language enum. Without it, the backend silently drops Ruby uploads.
# Revert this file: change @language = 'JAVA' back to @language = 'RUBY' on line ~36.
# Revert uploader.rb: change ddsource: 'dd_debugger' back to ddsource: 'ruby'.
# Then remove all TODO/TEMPORARY comments from both files.

require 'json'

module Datadog
  module SymbolDatabase
    # Top-level container wrapping scopes for upload to the agent.
    #
    # ServiceVersion is the root object serialized to JSON for symbol database uploads.
    # Contains service metadata (name, env, version) and all extracted scopes.
    # The language field identifies the tracer.
    # TEMPORARY: Using "JAVA" until debugger-backend#1974 adds RUBY to the storage
    # Language enum. Revert to "RUBY" once that PR merges.
    #
    # Created by: Uploader (wraps scopes array before serialization)
    # Contains: Array of top-level Scope objects (MODULE scopes)
    # Serialized to: JSON via to_json, then GZIP compressed for upload
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
      def initialize(service:, env:, version:, scopes:)
        raise ArgumentError, 'service is required' if service.nil? || service.empty?
        raise ArgumentError, 'scopes must be an array' unless scopes.is_a?(Array)

        @service = service
        @env = env.to_s.empty? ? 'none' : env.to_s
        @version = version.to_s.empty? ? 'none' : version.to_s
        @language = 'JAVA' # TEMPORARY: revert to 'RUBY' after debugger-backend#1974
        @scopes = scopes
      end

      # Convert service version to Hash for JSON serialization.
      # @return [Hash] ServiceVersion as hash with symbol keys
      def to_h
        {
          service: service,
          env: env,
          version: version,
          language: language,
          scopes: scopes.map(&:to_h)
        }
      end

      # Serialize service version to JSON.
      # @return [String] JSON string representation
      def to_json(_state = nil)
        JSON.generate(to_h)
      end
    end
  end
end
