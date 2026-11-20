# frozen_string_literal: true

require "json"
require_relative "rate_limiter"
require_relative "trace_keeper"
require_relative "compressed_json"

module Datadog
  module AppSec
    # AppSec event
    module Event
      ATTRIBUTES_SCHEMA_KEY_PREFIX = "_dd.appsec.s."
      ATTRIBUTES_SCHEMA_MAX_COMPRESSED_SIZE = 25000
      ALLOWED_REQUEST_HEADERS = %w[
        x-forwarded-for
        x-client-ip
        x-real-ip
        x-forwarded
        x-cluster-client-ip
        forwarded-for
        forwarded
        via
        true-client-ip
        content-length
        content-type
        content-encoding
        content-language
        host
        user-agent
        accept
        accept-encoding
        accept-language
      ].freeze

      class << self
        def tag(context, waf_result)
          return if context.span.nil?
          # libddwaf 2.0 can report a match for attributes alone, without a rule match.
          # Attribute-only output does not need the appsec.event tag.
          return if waf_result.events.empty? && waf_result.actions.empty?

          if waf_result.actions.key?("block_request") || waf_result.actions.key?("redirect_request")
            context.span.set_tag("appsec.blocked", "true")
          end

          context.span.set_tag("appsec.event", "true")
        end

        def record(context, request: nil)
          return if context.events.empty? || context.span.nil?

          Datadog::AppSec::RateLimiter.thread_local.limit do
            context.events.group_by(&:trace).each do |trace, event_group|
              unless trace
                next Datadog.logger.debug do
                  "AppSec: Cannot record event group with #{event_group.count} events because it has no trace"
                end
              end

              if event_group.any? { |event| event.keep? || event.schema? }
                TraceKeeper.keep!(trace)

                context.span["_dd.origin"] = "appsec"
                context.span.set_tags(request_tags(request)) if request
              end

              context.span.set_tags(waf_tags(event_group))
            end
          end
        end

        private

        def request_tags(request)
          tags = {}

          tags["http.host"] = request.host if request.host
          tags["http.useragent"] = request.user_agent if request.user_agent
          tags["network.client.ip"] = request.remote_addr if request.remote_addr

          request.headers.each_with_object(tags) do |(name, value), memo|
            next unless ALLOWED_REQUEST_HEADERS.include?(name)

            memo["http.request.headers.#{name}"] = value
          end
        end

        def waf_tags(security_events)
          triggers = []
          derivatives = {}

          security_events.each do |security_event|
            triggers.concat(security_event.waf_result.events)

            # Independent subcontexts can repeat derivatives; retain the request's first observations.
            derivatives.merge!(security_event.waf_result.attributes) { |_key, first_value, _new_value| first_value }
          end

          tags = derivatives.each_with_object({}) do |(key, value), memo|
            unless key.start_with?(ATTRIBUTES_SCHEMA_KEY_PREFIX)
              memo[key] = value
              next
            end

            value = CompressedJson.dump(value)
            next if value.nil?

            if value.size >= ATTRIBUTES_SCHEMA_MAX_COMPRESSED_SIZE
              Datadog.logger.debug { "AppSec: Schema key '#{key}' will not be included into span tags due to it's size" }
              next
            end

            memo[key] = value
          end

          tags["_dd.appsec.json"] = json_parse({triggers: triggers}) unless triggers.empty?
          tags
        end

        # NOTE: Handling of Encoding::UndefinedConversionError is added as a quick fix to
        #       the issue between Ruby encoded strings and libddwaf produced events and now
        #       is under investigation.
        def json_parse(value)
          JSON.dump(value)
        rescue ArgumentError, Encoding::UndefinedConversionError, JSON::JSONError => e
          AppSec.telemetry.report(e, description: "AppSec: Failed to convert value into JSON")

          nil
        end
      end
    end
  end
end
