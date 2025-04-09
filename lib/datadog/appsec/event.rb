# frozen_string_literal: true

require 'json'
require_relative 'rate_limiter'
require_relative 'compressed_json'

module Datadog
  module AppSec
    # AppSec event
    module Event
      DERIVATIVE_SCHEMA_KEY_PREFIX = '_dd.appsec.s.'
      DERIVATIVE_SCHEMA_MAX_COMPRESSED_SIZE = 25000
      ALLOWED_REQUEST_HEADERS = %w[
        X-Forwarded-For
        X-Client-IP
        X-Real-IP
        X-Forwarded
        X-Cluster-Client-IP
        Forwarded-For
        Forwarded
        Via
        True-Client-IP
        Content-Length
        Content-Type
        Content-Encoding
        Content-Language
        Host
        User-Agent
        Accept
        Accept-Encoding
        Accept-Language
      ].map!(&:downcase).freeze

      ALLOWED_RESPONSE_HEADERS = %w[
        Content-Length
        Content-Type
        Content-Encoding
        Content-Language
      ].map!(&:downcase).freeze

      # Record events for a trace
      #
      # This is expected to be called only once per trace for the rate limiter
      # to properly apply
      class << self
        def record(span, *events)
          # ensure rate limiter is called only when there are events to record
          return if events.empty? || span.nil?

          Datadog::AppSec::RateLimiter.thread_local.limit do
            record_via_span(span, *events)
          end
        end

        def record_via_span(span, *events)
          events.group_by { |e| e[:trace] }.each do |trace, event_group|
            unless trace
              Datadog.logger.debug { "{ error: 'no trace: cannot record', event_group: #{event_group.inspect}}" }
              next
            end

            trace.keep!
            trace.set_tag(
              Datadog::Tracing::Metadata::Ext::Distributed::TAG_DECISION_MAKER,
              Datadog::Tracing::Sampling::Ext::Decision::ASM
            )

            # prepare and gather tags to apply
            service_entry_tags = build_service_entry_tags(event_group)

            # apply tags to service entry span
            service_entry_tags.each do |key, value|
              span.set_tag(key, value)
            end
          end
        end

        def build_service_entry_tags(event_group)
          waf_events = []
          entry_tags = event_group.each_with_object({ '_dd.origin' => 'appsec' }) do |event, tags|
            # TODO: assume HTTP request context for now
            if (request = event[:request])
              request.headers.each do |header, value|
                tags["http.request.headers.#{header}"] = value if ALLOWED_REQUEST_HEADERS.include?(header.downcase)
              end

              tags['http.host'] = request.host
              tags['http.useragent'] = request.user_agent
              tags['network.client.ip'] = request.remote_addr
            end

            if (response = event[:response])
              response.headers.each do |header, value|
                tags["http.response.headers.#{header}"] = value if ALLOWED_RESPONSE_HEADERS.include?(header.downcase)
              end
            end

            waf_result = event[:waf_result]
            # accumulate triggers
            waf_events += waf_result.events

            waf_result.derivatives.each do |key, value|
              next tags[key] = value unless key.start_with?(DERIVATIVE_SCHEMA_KEY_PREFIX)

              value = CompressedJson.dump(value)
              next if value.nil?

              if value.size >= DERIVATIVE_SCHEMA_MAX_COMPRESSED_SIZE
                Datadog.logger.debug { "AppSec: Schema key '#{key}' will not be included into span tags due to it's size" }
                next
              end

              tags[key] = value
            end

            tags
          end

          appsec_events = json_parse({ triggers: waf_events })
          entry_tags['_dd.appsec.json'] = appsec_events if appsec_events
          entry_tags
        end

        def tag_and_keep!(context, waf_result)
          # We want to keep the trace in case of security event
          context.trace.keep! if context.trace

          if context.span
            context.span.set_tag('appsec.blocked', 'true') if waf_result.actions.key?('block_request')
            context.span.set_tag('appsec.event', 'true')
          end

          add_distributed_tags(context.trace)
        end

        private

        def json_parse(value)
          JSON.dump(value)
        rescue ArgumentError, JSON::JSONError => e
          Datadog.logger.debug do
            "Failed to parse value to JSON when populating AppSec::Event. Error: #{e.message}"
          end
          nil
        end

        # Propagate to downstream services the information that the current distributed trace is
        # containing at least one ASM security event.
        def add_distributed_tags(trace)
          return unless trace

          trace.set_tag(
            Datadog::Tracing::Metadata::Ext::Distributed::TAG_DECISION_MAKER,
            Datadog::Tracing::Sampling::Ext::Decision::ASM
          )
          trace.set_distributed_source(Datadog::AppSec::Ext::PRODUCT_BIT)
        end
      end
    end
  end
end
