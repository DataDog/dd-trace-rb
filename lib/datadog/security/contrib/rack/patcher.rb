# typed: ignore

require 'datadog/security/contrib/patcher'
require 'datadog/security/contrib/rack/integration'

module Datadog
  module Security
    module Contrib
      module Rack
        # Patcher for Rack integration
        module Patcher
          include Datadog::Security::Contrib::Patcher

          module_function

          def patched?
            Patcher.instance_variable_get(:@patched)
          end

          def target_version
            Integration.version
          end

          def patch
            Instrumentation.gateway.watch('rack.request') do |request|
              block = false
              waf_context = request.env['datadog.waf.context']
              waf_rules = request.env['datadog.waf.rules']

              Reactive::Operation.new('rack.request') do |op|
                if defined?(Datadog::Tracer) && Datadog.respond_to?(:tracer) && (tracer = Datadog.tracer)
                  root_span = tracer.active_root_span
                  active_span = tracer.active_span

                  Datadog.logger.debug { "root span: #{root_span.span_id}" } if root_span
                  Datadog.logger.debug { "active span: #{active_span.span_id}" } if active_span

                  root_span.set_tag('_dd.appsec.enabled', 1)
                  root_span.set_tag('_dd.runtime_family', 'ruby')
                end

                addresses = [
                  'request.headers',
                  'request.uri.raw',
                  'request.query',
                  'request.cookies',
                  'request.body',
                  # TODO: 'request.path_params',
                ]
                op.subscribe(*addresses) do |*values|
                  Datadog.logger.debug { "reacted to #{addresses.inspect}: #{values.inspect}" }
                  headers = values[0]
                  headers_no_cookies = headers.dup.tap { |h| h.delete('cookie') }
                  uri_raw = values[1]
                  query = values[2]
                  cookies = values[3]
                  body = values[4]
                  Datadog.logger.debug { "headers: #{headers}" }
                  Datadog.logger.debug { "headers_no_cookie: #{headers_no_cookies}" }

                  waf_args = {
                    'server.request.cookies' => cookies,
                    'server.request.body' => body,
                    'server.request.query' => query,
                    'server.request.uri.raw' => uri_raw,
                    'server.request.headers' => headers,
                    'server.request.headers.no_cookies' => headers_no_cookies,
                    # TODO: 'server.request.path_params' => path_params,
                  }

                  # TODO: this check is too low level
                  # TODO: raise a proper exception
                  raise if waf_context.context_obj.null?

                  action, result = waf_context.run(waf_args)

                  case action
                  when :monitor
                    Datadog.logger.debug { "WAF: #{result.inspect}" }
                    if active_span
                      active_span.set_tag('appsec.action', 'monitor')
                      active_span.set_tag('appsec.event', 'true')
                      active_span.set_tag(Datadog::Ext::ManualTracing::TAG_KEEP, true)
                    end
                    record_event({ waf_result: result, waf_rules: waf_rules, span: active_span, request: request }, false)
                  when :block
                    Datadog.logger.debug { "WAF: #{result.inspect}" }
                    if active_span
                      active_span.set_tag('appsec.action', 'block')
                      active_span.set_tag('appsec.event', 'true')
                      active_span.set_tag(Datadog::Ext::ManualTracing::TAG_KEEP, true)
                    end
                    record_event({ waf_result: result, waf_rules: waf_rules, span: active_span, request: request }, true)
                    block = true
                  when :good
                    Datadog.logger.debug { "WAF OK: #{result.inspect}" }
                  when :timeout
                    Datadog.logger.debug { "WAF TIMEOUT: #{result.inspect}" }
                  when :invalid_call
                    Datadog.logger.debug { "WAF CALL ERROR: #{result.inspect}" }
                  when :invalid_rule, :invalid_flow, :no_rule
                    Datadog.logger.debug { "WAF RULE ERROR: #{result.inspect}" }
                  else
                    Datadog.logger.debug { "WAF UNKNOWN: #{action.inspect} #{result.inspect}" }
                  end

                  throw(:block, :block) if block
                end

                block = catch(:block) do
                  # TODO: extract header transformation and query string processing
                  op.publish('request.query', request.query_string.split('&').map { |e| e.split('=').map { |s| CGI.unescape(s) } })
                  op.publish('request.headers', (request.each_header.each_with_object({}) { |(k, v), h| h[k.gsub(/^HTTP_/, '').downcase.gsub('_', '-')] = v if k =~ /^HTTP_/ }))
                  op.publish('request.uri.raw', request.url)
                  op.publish('request.cookies', request.cookies)
                  # TODO: op.publish('request.path_params', { k: v }) # route params only?
                  # TODO: op.publish('request.path', request.script_name + request.path) # unused for now
                  body = request.body.read
                  request.body.rewind
                  op.publish('request.body', body)
                  nil
                end
              end if defined?(Datadog::Security::WAF)

              block
            end

            Patcher.instance_variable_set(:@patched, true)
          end

          def record_event(data, blocked)
            span = data[:span]
            request = data[:request]
            env = Datadog.configuration.env
            tags = Datadog.configuration.tags
            rules = data[:waf_rules]

            timestamp = Time.now.utc.iso8601

            tags = [
              '_dd.appsec.enabled:1',
              '_dd.runtime_family:ruby',
            ]
            tags << "service:#{span.service}"
            tags << "env:#{env}" if env

            # TODO: extract header transformation
            request_headers = request.each_header.each_with_object({}) { |(k, v), h| h[k.gsub(/^HTTP_/, '').downcase.tr('_', '-')] = v if k =~ /^HTTP_/ }
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
                        # status: 200, # TODO: requires sending event after request
                        blocked: blocked,
                        # headers: {}, # TODO: requires sending event after request
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
  end
end
