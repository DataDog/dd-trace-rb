# frozen_string_literal: true

require 'json'

require_relative 'scope'

module Datadog
  module SymbolDatabase
    # Top-level upload payload wrapper.
    #
    # @api private
    class ServiceVersion
      attr_reader :service, :env, :version, :language, :scopes

      def initialize(service:, env:, version:, scopes:)
        raise ArgumentError, 'service is required' if service.nil? || service.empty?
        raise ArgumentError, 'scopes must be an array' unless scopes.is_a?(Array)

        @service = service
        @env = env.to_s.empty? ? 'none' : env.to_s
        @version = version.to_s.empty? ? 'none' : version.to_s
        @language = 'ruby'
        @scopes = scopes
      end

      def to_h
        {
          service: service,
          env: env,
          version: version,
          language: language,
          scopes: scopes.map(&:to_h),
        }
      end

      def to_json(_state = nil)
        JSON.generate(to_h)
      end
    end
  end
end
