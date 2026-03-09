# frozen_string_literal: true

module Datadog
  module SymbolDatabase
    # Represents the top-level service version container for symbol upload
    class ServiceVersion
      attr_reader :service, :env, :version, :language, :scopes

      def initialize(service:, env:, version:, scopes:)
        raise ArgumentError, 'service is required' if service.nil? || service.empty?
        raise ArgumentError, 'scopes must be an array' unless scopes.is_a?(Array)

        @service = service
        @env = env.to_s.empty? ? 'none' : env.to_s
        @version = version.to_s.empty? ? 'none' : version.to_s
        @language = 'RUBY'
        @scopes = scopes
      end

      # Convert service version to Hash for JSON serialization
      def to_h
        {
          service: service,
          env: env,
          version: version,
          language: language,
          scopes: scopes.map(&:to_h)
        }
      end

      # Serialize service version to JSON
      def to_json(*args)
        require 'json'
        JSON.generate(to_h, *args)
      end
    end
  end
end
