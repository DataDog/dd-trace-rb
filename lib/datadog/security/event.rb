module Datadog
  module Security
    module Event
      def self.record(data, blocked)
        span = data[:span]
        request = data[:request]
        response = data[:response]
        env = Datadog.configuration.env
        tags = Datadog.configuration.tags

        timestamp = Time.now.utc.iso8601

        tags = [
          '_dd.appsec.enabled:1',
          '_dd.runtime_family:ruby',
        ]
        tags << "service:#{span.service}"
        tags << "env:#{env}" if env

        request_headers = Security::Contrib::Rack::Request.headers(request)
        hostname = Socket.gethostname
        platform = RUBY_PLATFORM
        os_type = case platform
                  when /darwin/ then 'Mac OS X'
                  when /linux/ then 'Linux'
                  when /mingw/ then 'Windows'
                  end

        events = []

        data[:waf_result].data.each do |waf|
          rule = waf['rule']
          waf['rule_matches'].each do |match|
            event = {
              event_id: SecureRandom.uuid,
              event_type: 'appsec.threat.attack',
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
                    headers: response.headers,
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
                  runtime_type: RUBY_ENGINE,
                  runtime_version: RUBY_VERSION,
                  lib_version: Datadog::VERSION::STRING,
                }
              }
            }

            events << event
          end
        end

        Datadog::Security.writer.write(events)
      end
    end
  end
end
