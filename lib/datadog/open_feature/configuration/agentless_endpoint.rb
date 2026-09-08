# frozen_string_literal: true

require "uri"

module Datadog
  module OpenFeature
    module Configuration
      # Validated endpoint for agentless Feature Flags configuration delivery.
      class AgentlessEndpoint
        DEFAULT_SITE = "datadoghq.com"
        CONFIGURATION_PATH = "/api/v2/feature-flagging/config/rules-based/server"
        INVALID_SITE_CHARACTERS = /[\s\/?#@:]/
        INTERNAL_WHITESPACE = /\s/

        attr_reader :uri

        def self.build(site:, environment:, base_url: nil, logger: Datadog.logger)
          if base_url
            build_custom(base_url, logger)
          else
            build_managed(site, environment, logger)
          end
        end

        def initialize(uri, managed:)
          @uri = uri
          @managed = managed
        end

        def managed?
          @managed
        end

        def self.build_custom(base_url, logger)
          if base_url.match?(INTERNAL_WHITESPACE)
            logger.warn("Feature Flags agentless base URL contains whitespace; agentless delivery is disabled")
            return
          end

          uri = URI.parse(base_url)
          unless uri.is_a?(URI::HTTP) && uri.host
            logger.warn("Feature Flags agentless base URL must be an absolute HTTP or HTTPS URL; agentless delivery is disabled")
            return
          end

          uri.path = CONFIGURATION_PATH if uri.path.empty? || uri.path == "/"
          new(uri, managed: false)
        rescue URI::InvalidURIError
          logger.warn("Feature Flags agentless base URL is invalid; agentless delivery is disabled")
          nil
        end
        private_class_method :build_custom

        def self.build_managed(site, environment, logger)
          normalized_site = site.to_s.strip.downcase
          normalized_site = DEFAULT_SITE if normalized_site.empty?
          if normalized_site.match?(INVALID_SITE_CHARACTERS)
            logger.warn("Feature Flags site is invalid; agentless delivery is disabled")
            return
          end

          uri = URI::HTTPS.build(
            host: "ufc-server.ff-cdn.#{normalized_site}",
            path: CONFIGURATION_PATH,
            query: environment.nil? ? nil : URI.encode_www_form(dd_env: environment),
          )
          new(uri, managed: true)
        rescue URI::InvalidComponentError
          logger.warn("Feature Flags site is invalid; agentless delivery is disabled")
          nil
        end
        private_class_method :build_managed
      end
    end
  end
end
