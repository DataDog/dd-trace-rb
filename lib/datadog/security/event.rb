require 'datadog/security/contrib/rack/request'
require 'datadog/security/contrib/rack/response'
require 'datadog/security/rate_limiter'

module Datadog
  module AppSec
    module Event
      ALLOWED_REQUEST_HEADERS = [
        'X-Forwarded-For',
        'X-Client-IP',
        'X-Real-IP',
        'X-Forwarded',
        'X-Cluster-Client-IP',
        'Forwarded-For',
        'Forwarded',
        'Via',
        'True-Client-IP',
        'Content-Length',
        'Content-Type',
        'Content-Encoding',
        'Content-Language',
        'Host',
        'User-Agent',
        'Accept',
        'Accept-Encoding',
        'Accept-Language',
      ].map!(&:downcase)

      ALLOWED_RESPONSE_HEADERS = [
        'Content-Length',
        'Content-Type',
        'Content-Encoding',
        'Content-Language',
      ].map!(&:downcase)

      def self.record(*events)
        Datadog::AppSec::RateLimiter.limit(:traces) do
          record_via_span(*events)
        end
      end

      def self.record_via_span(*events)
        events.group_by { |e| e[:root_span] }.each do |root_span, event_group|
          unless root_span
            Datadog.logger.debug { "{ error: 'no root span: cannot record', event_group: #{event_group.inspect}}" }
            next
          end

          # TODO: this is a hack but there is no API to do that
          root_span_tags = root_span.send(:meta).keys

          # prepare and gather tags to apply
          tags = event_group.each_with_object({}) do |event, tags|
            span = event[:span]
            trace = event[:trace]

            if span
              span.set_tag('appsec.event', 'true')
              trace.keep!  # span.set_tag(Datadog::Ext::ManualTracing::TAG_KEEP, true)
            end

            request = event[:request]
            response = event[:response]

            # TODO: assume HTTP request context for now
            request_headers = AppSec::Contrib::Rack::Request.headers(request)
              .select { |k, _| ALLOWED_REQUEST_HEADERS.include?(k.downcase) }
            response_headers = AppSec::Contrib::Rack::Response.headers(response)
              .select { |k, _| ALLOWED_RESPONSE_HEADERS.include?(k.downcase) }

            request_headers.each do |header, value|
              tags["http.request.headers.#{header}"] = value
            end

            response_headers.each do |header, value|
              tags["http.response.headers.#{header}"] = value
            end

            tags['http.host'] = request.host
            tags['http.useragent'] = request.user_agent
            tags['network.client.ip'] = request.ip

            # tags['actor.ip'] = request.ip # TODO: uses client IP resolution algorithm
            tags['_dd.origin'] = 'appsec'

            # accumulate triggers
            tags['_dd.appsec.triggers'] ||= []
            tags['_dd.appsec.triggers'] += event[:waf_result].data
          end

          # apply tags to root span

          # complex types are unsupported, we need to serialize to a string
          triggers = tags.delete('_dd.appsec.triggers')
          root_span.set_tag('_dd.appsec.json', JSON.dump({triggers: triggers}))

          tags.each do |key, value|
            unless root_span_tags.map { |tag| tag =~ /\.headers\./ ? tag.tr('_', '-') : tag }.include?(key)
              root_span.set_tag(key, value.is_a?(String) ? value.encode('UTf-8') : value)
            end
          end
        end
      end
    end
  end
end
