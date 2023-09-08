require 'json'

require_relative 'rate_limiter'

module Datadog
  module AppSec
    # AppSec event
    module Event
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
      def self.record(span, *events)
        # ensure rate limiter is called only when there are events to record
        return if events.empty? || span.nil?

        Datadog::AppSec::RateLimiter.limit(:traces) do
          record_via_span(span, *events)
        end
      end

      def self.record_via_span(span, *events)
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
          # complex types are unsupported, we need to serialize to a string
          triggers = service_entry_tags.delete('_dd.appsec.triggers')
          span.set_tag('_dd.appsec.json', JSON.dump({ triggers: triggers }))

          # apply tags to service entry span
          service_entry_tags.each do |key, value|
            span.set_tag(key, value)
          end
        end
      end

      def self.build_service_entry_tags(event_group)
        event_group.each_with_object({}) do |event, tags|
          # TODO: assume HTTP request context for now

          if (request = event[:request])
            request_headers = request.headers.select do |k, _|
              ALLOWED_REQUEST_HEADERS.include?(k.downcase)
            end

            request_headers.each do |header, value|
              tags["http.request.headers.#{header}"] = value
            end

            tags['http.host'] = request.host
            tags['http.useragent'] = request.user_agent
            tags['network.client.ip'] = request.remote_addr
          end

          if (response = event[:response])
            response_headers = response.headers.select do |k, _|
              ALLOWED_RESPONSE_HEADERS.include?(k.downcase)
            end

            response_headers.each do |header, value|
              tags["http.response.headers.#{header}"] = value
            end
          end

          tags['_dd.origin'] = 'appsec'

          # accumulate triggers
          tags['_dd.appsec.triggers'] ||= []
          tags['_dd.appsec.triggers'] += event[:waf_result].events
        end
      end
    end
  end
end
