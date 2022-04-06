# typed: false

require 'datadog/appsec/contrib/rack/request'
require 'datadog/appsec/contrib/rack/response'
require 'datadog/appsec/rate_limiter'

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

      def self.record(*events)
        Datadog::AppSec::RateLimiter.limit(:traces) do
          record_via_span(*events)
        end
      end

      # rubocop:disable Metrics/AbcSize
      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/PerceivedComplexity
      # rubocop:disable Metrics/CyclomaticComplexity
      def self.record_via_span(*events)
        events.group_by { |e| e[:trace] }.each do |trace, event_group|
          unless trace
            Datadog.logger.debug { "{ error: 'no trace: cannot record', event_group: #{event_group.inspect}}" }
            next
          end

          trace.keep!

          # prepare and gather tags to apply
          trace_tags = event_group.each_with_object({}) do |event, tags|
            span = event[:span]

            span.set_tag('appsec.event', 'true') if span

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
              tags['network.client.ip'] = request.ip

              # tags['actor.ip'] = request.ip # TODO: uses client IP resolution algorithm
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
          previous_triggers = if (json = trace.send(:get_tag, '_dd.appsec.json'))
                                JSON.parse(json)['triggers']
                              else
                                []
                              end
          trace.set_tag('_dd.appsec.json', JSON.dump({ triggers: previous_triggers + triggers }))

          trace_tags.each do |key, value|
            trace.set_tag(key, value)
          end
        end
      end
      # rubocop:enable Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/MethodLength
      # rubocop:enable Metrics/PerceivedComplexity
      # rubocop:enable Metrics/AbcSize
    end
  end
end
