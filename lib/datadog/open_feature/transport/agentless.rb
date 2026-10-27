# frozen_string_literal: true

require_relative "../../core/encoding"
require_relative "../../core/evp"
require_relative "../../core/utils/time"
require_relative "http_client"

module Datadog
  module OpenFeature
    module Transport
      # Component-owned route selection shared by both event writers.
      class Agentless
        DISCOVERY_TIMEOUT_SECONDS = 1
        REQUEST_TIMEOUT_SECONDS = 2
        RECOVERY_INTERVAL_SECONDS = 30
        LOCAL_ROUTES = ["/evp_proxy/v4", "/evp_proxy/v2"].freeze

        def initialize(agent_settings:, site:, api_key:, logger:)
          @client = HTTPClient.new(agent_settings: agent_settings, site: site, api_key: api_key)
          @logger = logger
          @mutex = Mutex.new
          @fork_mutex = Mutex.new
          @route = nil
          @recover_at = 0.0
          @pid = Process.pid
          @closed = false
          @shutdown_deadline = nil
        end

        def send_exposures(payload)
          send_batch("/api/v2/exposures", payload)
        end

        def send_flag_evaluations(payload)
          send_batch("/api/v2/flagevaluation", payload)
        end

        def shutdown!(timeout:)
          reset_after_fork
          @shutdown_deadline = Core::Utils::Time.get_time + timeout
        end

        def close
          @closed = true
        end

        private

        def send_batch(path, payload)
          encoded = Core::Encoding::JSONEncoder.encode(payload)
          route = select_route
          return Response.new unless route

          response = send_once(route, path, encoded)
          if route != :direct && (response.internal_error? || [403, 404, 405, 429].include?(response.code) ||
              response.code&.between?(500, 599))
            fallback = leave_local(route)
            if fallback && (response.pre_send? || [404, 405].include?(response.code))
              response = send_once(:direct, path, encoded)
            end
          end
          @logger.debug { "OpenFeature EVP: batch dropped after delivery failure" } unless response.ok?
          response
        # Serialization and delivery failures must never interrupt flag evaluation or reveal event data.
        rescue
          @logger.debug { "OpenFeature EVP: batch dropped after internal delivery failure" }
          Response.new
        end

        def send_once(route, path, encoded)
          direct = route == :direct
          @client.request(direct ? path : route.to_s + path,
            payload: encoded, direct: direct, timeout: remaining(REQUEST_TIMEOUT_SECONDS))
        end

        def select_route
          reset_after_fork
          @mutex.synchronize do
            return if @closed || remaining(REQUEST_TIMEOUT_SECONDS) <= 0
            return @route if @route || Core::Utils::Time.get_time < @recover_at

            info = @client.request("/info", timeout: remaining(DISCOVERY_TIMEOUT_SECONDS)).info
            @route = compatible_route(info)
            @route = :direct if !@route && @client.direct?
            @recover_at = Core::Utils::Time.get_time + RECOVERY_INTERVAL_SECONDS unless @route
            @route
          end
        end

        def compatible_route(info)
          return unless info

          headers = info["evp_proxy_allowed_headers"]
          endpoints = info["endpoints"]
          return unless headers.is_a?(Array) && endpoints.is_a?(Array)

          headers = headers.grep(String).map { |header| header.strip.downcase }
          return unless HTTPClient::IDENTITY_HEADERS.keys.all? { |name| headers.include?(name.downcase) }

          LOCAL_ROUTES.find { |path| endpoints.include?(path) || endpoints.include?(path + "/") }
        end

        def leave_local(route)
          @mutex.synchronize do
            return false if @closed

            if @route == route
              @route = @client.direct? ? :direct : nil
              @recover_at = Core::Utils::Time.get_time + RECOVERY_INTERVAL_SECONDS unless @route
            end
            @route == :direct
          end
        end

        def remaining(limit)
          return 0 if @closed

          deadline = @shutdown_deadline
          deadline ? [limit, deadline - Core::Utils::Time.get_time].min : limit
        end

        def reset_after_fork
          return if @pid == Process.pid

          @fork_mutex.synchronize do
            return if @pid == Process.pid

            @mutex = Mutex.new
            @route = nil
            @recover_at = 0.0
            @shutdown_deadline = nil
            @pid = Process.pid
          end
        end
      end
    end
  end
end
