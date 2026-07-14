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
    # Contains: Array of top-level Scope objects (FILE scopes)
    # Serialized to: JSON via to_json, then GZIP compressed for upload
    #
    # @api private
    class ServiceVersion
      attr_reader :service, :env, :version, :language, :scopes, :upload_id, :batch_num, :final

      # Initialize a new ServiceVersion
      # @param service [String] Service name (required, from DD_SERVICE)
      # @param env [String, nil] Environment (from DD_ENV, passed through unchanged)
      # @param version [String, nil] Version (from DD_VERSION, passed through unchanged)
      # @param scopes [Array<Scope>] Top-level scopes (required)
      # @param upload_id [String, nil] UUID identifying the logical upload (shared by all batches)
      # @param batch_num [Integer, nil] 1-indexed batch number within the upload
      # @param final [Boolean, nil] true if this is the last batch of the upload
      # @raise [ArgumentError] if service empty or scopes not an array
      def initialize(service:, env:, version:, scopes:, upload_id: nil, batch_num: nil, final: nil)
        raise ArgumentError, 'service is required' if service.nil? || service.empty?
        raise ArgumentError, 'scopes must be an array' unless scopes.is_a?(Array)

        @service = service
        @env = env
        @version = version
        @language = 'ruby'
        @scopes = scopes
        @upload_id = upload_id
        @batch_num = batch_num
        @final = final
      end

      # Convert service version to Hash for JSON serialization.
      # @return [Hash] ServiceVersion as hash with symbol keys
      def to_h
        {
          service: service,
          env: env,
          version: version,
          language: language,
          scopes: scopes.map(&:to_h),
          upload_id: upload_id,
          batch_num: batch_num,
          final: final,
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
