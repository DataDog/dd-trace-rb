require 'json'

require_relative 'contrib/rack/request'
require_relative 'contrib/rack/response'
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
      def self.record(*events)
        # ensure rate limiter is called only when there are events to record
        return if events.empty?

        Datadog::AppSec::RateLimiter.limit(:traces) do
          record_via_span(*events)
        end
      end

      # rubocop:disable Metrics/MethodLength
      def self.record_via_span(*events) # rubocop:disable Metrics/AbcSize
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
          trace_tags = event_group.each_with_object({}) do |event, tags|
            # TODO: assume HTTP request context for now

            if (request = event[:request])
              request_headers = AppSec::Contrib::Rack::Request.headers(request).select do |k, _|
                ALLOWED_REQUEST_HEADERS.include?(k.downcase)
              end

              request_headers.each do |header, value|
                tags["http.request.headers.#{header}"] = value
              end

              tags['http.host'] = request.host
              tags['http.useragent'] = request.user_agent
              tags['network.client.ip'] = request.env['REMOTE_ADDR'] if request.env['REMOTE_ADDR']
            end

            if (response = event[:response])
              response_headers = AppSec::Contrib::Rack::Response.headers(response).select do |k, _|
                ALLOWED_RESPONSE_HEADERS.include?(k.downcase)
              end

              response_headers.each do |header, value|
                tags["http.response.headers.#{header}"] = value
              end
            end

            tags['_dd.origin'] = 'appsec'

            # accumulate triggers
            tags['_dd.appsec.triggers'] ||= []
            tags['_dd.appsec.triggers'] += event[:waf_result].data
          end

          # apply tags to root span

          # complex types are unsupported, we need to serialize to a string
          triggers = trace_tags.delete('_dd.appsec.triggers')
          trace.set_tag('_dd.appsec.json', JSON.dump({ triggers: triggers }))

          trace_tags.each do |key, value|
            trace.set_tag(key, value)
          end
        end
      end
      # rubocop:enable Metrics/MethodLength
    end
  end
end
