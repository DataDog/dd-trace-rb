require 'datadog/security/contrib/rack/request'
require 'datadog/security/contrib/rack/response'

module Datadog
  module Security
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
        transport = :span
        #transport = :api

        case transport
        when :span
          record_via_span(*events)
        when :api
          record_via_api(*events)
        end
      end

      def self.record_via_span(*events)
        events.group_by { |e| e[:root_span] }.each do |root_span, event_group|
          unless root_span
            Datadog.logger.debug { "{ error: 'no root span: cannot record', event_group: #{event_group.inspect}}" }
            next
          end

          # TODO: this is a hack but there is no API to do that
          root_span_tags = root_span.instance_eval { @meta }.keys

          # prepare and gather tags to apply
          tags = event_group.each_with_object({}) do |event, tags|
            span = event[:span]

            if span
              span.set_tag('appsec.event', 'true')
              span.set_tag(Datadog::Ext::ManualTracing::TAG_KEEP, true)
            end

            request = event[:request]
            response = event[:response]

            # TODO: assume HTTP request context for now
            request_headers = Security::Contrib::Rack::Request.headers(request)
              .select { |k, _| ALLOWED_REQUEST_HEADERS.include?(k.downcase) }
            response_headers = Security::Contrib::Rack::Response.headers(response)
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

      def self.record_via_api(*events)
        events.each do |data|
          span = data[:span]
          request = data[:request]
          response = data[:response]
          action = data[:action]
          env = Datadog.configuration.env
          tags = Datadog.configuration.tags

          blocked = action == :block

          if span
            span.set_tag('appsec.event', 'true')
            span.set_tag(Datadog::Ext::ManualTracing::TAG_KEEP, true)
          end

          # TODO: move to event occurence
          timestamp = Time.now.utc.iso8601

          tags = [
            '_dd.appsec.enabled:1',
            '_dd.runtime_family:ruby',
          ]
          tags << "service:#{span.service}"
          tags << "env:#{env}" if env

          request_headers = Security::Contrib::Rack::Request.headers(request)
                            .select { |k, _| ALLOWED_REQUEST_HEADERS.include?(k.downcase) }
          response_headers = Security::Contrib::Rack::Response.headers(response)
                            .select { |k, _| ALLOWED_RESPONSE_HEADERS.include?(k.downcase) }
          hostname = Socket.gethostname
          platform = RUBY_PLATFORM
          os_type = case platform
                    when /darwin/ then 'Mac OS X'
                    when /linux/ then 'Linux'
                    when /mingw/ then 'Windows'
                    end
          runtime_type = RUBY_ENGINE
          runtime_version = RUBY_VERSION
          lib_version = Datadog::VERSION::STRING

          event_type = 'appsec.threat.attack'

          events = []

          data[:waf_result].data.each do |waf|
            rule = waf['rule']
            waf['rule_matches'].each do |match|
              event_id = SecureRandom.uuid
              event = for_api_transport(
                event_id,
                event_type,
                timestamp,
                rule,
                blocked,
                match,
                request,
                os_type,
                hostname,
                request_headers,
                response,
                response_headers,
                span,
                env,
                tags,
                runtime_type,
                runtime_version,
                lib_version,
              )

              events << event
            end
          end

          Datadog::Security.writer.write(events)
        end
      end

      def self.for_api_transport(event_id, event_type, timestamp, rule, blocked, match, request, os_type, hostname, request_headers, response, response_headers, span, env, tags, runtime_type, runtime_version, lib_version)
        {
          event_id: event_id,
          event_type: event_type,
          event_version: '0.1.0',
          detected_at: timestamp,
          type: rule['tags']['type'],
          blocked: blocked,
          rule: {
            id: rule['id'],
            name: rule['name'],
            set: rule['tags']['type'],
          },
          rule_match: {
            operator: match['operator'],
            operator_value: match['operator_value'],
            parameters: (match['parameters'].map do |parameter|
              {
                name: parameter['address'],
                key_path: parameter['key_path'],
                value: parameter['value'],
                highlight: parameter['highlight'],
              }
            end),
          },
          context: {
            actor: {
              context_version: '0.1.0',
              ip: {
                address: request.ip,
              },
              identifiers: nil,
              _id: nil,
            },
            host: {
              os_type: os_type,
              hostname: hostname,
              context_version: '0.1.0'
            },
            http: {
              context_version: '0.1.0',
              request: {
                scheme: request.scheme,
                method: request.request_method,
                url: request.url,
                host: request.host,
                port: request.port,
                path: request.path,
                # resource: '/hi', # route e.g /hi/:id # TODO: rails+sinatra only
                remote_ip: request.ip,
                # remote_port: , # TODO: not possible?
                headers: request_headers,
                useragent: request.user_agent,
              },
              response: {
                status: response.status,
                blocked: blocked,
                headers: response_headers,
              }
            },
            service: {
              context_version: '0.1.0',
              name: span.service,
              environment: env,
              # version: '1.0', # TODO: unsure what this is
            },
            span: {
              context_version: '0.1.0',
              id: span.span_id,
            },
            tags: {
              context_version: '0.1.0',
              values: tags,
            },
            trace: {
              context_version: '0.1.0',
              id: span.trace_id,
            },
            tracer: {
              context_version: '0.1.0',
              runtime_type: runtime_type,
              runtime_version: runtime_version,
              lib_version: lib_version,
            }
          }
        }
      end
    end
  end
end
