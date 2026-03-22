# frozen_string_literal: true

require 'json'

module Datadog
  module SymbolDatabase
    # Top-level payload wrapper for symbol uploads.
    class ServiceVersion
      attr_accessor :service, :env, :version, :language, :scopes

      def initialize(service:, env:, version:, language: 'RUBY', scopes: [])
        @service = service
        @env = env
        @version = version
        @language = language
        @scopes = scopes
      end

      def to_h
        h = {
          service: @service,
          env: @env,
          version: @version,
          language: @language,
        }
        h[:scopes] = @scopes.map(&:to_h) unless @scopes.empty?
        h
      end

      def to_json(*_args)
        JSON.generate(to_h)
      end
    end
  end
end
