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

      ALLOWED_RESPONSE_HEADERS = %w[
        content-length
        content-type
        content-encoding
        content-language
      ].freeze

      # Record events for a trace
      #
      # This is expected to be called only once per trace for the rate limiter
      # to properly apply
      class << self
        def tag_and_keep!(context, waf_result)
          # We want to keep the trace in case of security event
          context.trace.keep! if context.trace

          if context.span
            if waf_result.actions.key?('block_request') || waf_result.actions.key?('redirect_request')
              context.span.set_tag('appsec.blocked', 'true')
            end

            context.span.set_tag('appsec.event', 'true')
          end

          add_distributed_tags(context.trace)
        end

        def record(context, request: nil, response: nil)
          # ensure rate limiter is called only when there are events to record
          return if context.events.empty? || context.span.nil?

          Datadog::AppSec::RateLimiter.thread_local.limit do
            context.events.group_by { |e| e[:trace] }.each do |trace, event_group|
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
              service_entry_tags = events_tags(event_group)

              # apply tags to service entry span
              service_entry_tags.each do |key, value|
                context.span.set_tag(key, value)
              end

              context.span.set_tags(request_tags(request)) if request
              context.span.set_tags(response_tags(response)) if response
            end
          end
        end

        private

        def request_tags(request)
          tags = {}

          tags['http.host'] = request.host if request.host
          tags['http.useragent'] = request.user_agent if request.user_agent
          tags['network.client.ip'] = request.remote_addr if request.remote_addr

          request.headers.each_with_object(tags) do |(name, value), memo|
            next unless ALLOWED_REQUEST_HEADERS.include?(name)

            memo["http.request.headers.#{name}"] = value
          end
        end

        def response_tags(response)
          response.headers.each_with_object({}) do |(name, value), memo|
            next unless ALLOWED_RESPONSE_HEADERS.include?(name)

            memo["http.response.headers.#{name}"] = value
          end
        end

        def events_tags(event_group)
          waf_events = []
          entry_tags = event_group.each_with_object({ '_dd.origin' => 'appsec' }) do |event, tags|
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

        # NOTE: Handling of Encoding::UndefinedConversionError is added as a quick fix to
        #       the issue between Ruby encoded strings and libddwaf produced events and now
        #       is under investigation.
        def json_parse(value)
          JSON.dump(value)
        rescue ArgumentError, Encoding::UndefinedConversionError, JSON::JSONError => e
          AppSec.telemetry.report(e, description: 'AppSec: Failed to convert value into JSON')

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
