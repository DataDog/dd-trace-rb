require 'datadog/security/contrib/patcher'
require 'datadog/security/contrib/rack/integration'

module Datadog
  module Security
    module Contrib
      module Rack
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

              Reactive::Operation.new('rack.request') do |op|
                if defined?(Datadog::Tracer) && Datadog.respond_to?(:tracer) && (tracer = Datadog.tracer)
                  root_span = Datadog.tracer.active_root_span
                  active_span = Datadog.tracer.active_span

                  Datadog.logger.debug { "root span: #{root_span.span_id}"} if root_span
                  Datadog.logger.debug { "active span: #{active_span.span_id}"} if active_span

                  root_span.set_tag('_dd.appsec.enabled', 1)
                  root_span.set_tag('_dd.runtime_family', 'ruby')
                end

                addresses = [
                  #'request.user_agent',
                  #'request.params',
                  'request.headers',
                  #'request.referer',
                  #'request.path',
                ]
                op.subscribe(*addresses) do |*values|
                  headers = values[0]
                  #user_agent = values[0]
                  #params = values[1]
                  #headers = values[2]
                  #referer = values[3]
                  #path = values[4]
                  Datadog.logger.debug { "headers: #{headers}"}

                  waf_args = {
                    # 'server.request.cookies'
                    # 'server.request.body' =>
                    #'server.request.query' => params.keys.flatten,
                    #'server.request.path_params' => params.values.flatten,
                    'server.request.headers' => headers,
                    'server.request.headers.no_cookies' => headers, # TODO: strip cookies
                    #"#.request.env['HTTP_REFERER']" => referer,
                    #'#.client_user_agent' => user_agent,
                    #'#.request_path' => path,
                  }
                  #Datadog.logger.debug { "WAF args:\n" << JSON.pretty_generate(waf_args) }

                  fail if waf_context.context_obj.null?
                  action, result = waf_context.run(waf_args)

                  case action
                  when :monitor
                    Datadog.logger.debug { "WAF: #{result.inspect}" }
                    if active_span
                      active_span.set_tag('appsec.action', 'monitor')
                      active_span.set_tag('appsec.event', 'true')
                      active_span.set_tag(Datadog::Ext::ManualTracing::TAG_KEEP, true)
                    end
                    record_event({ waf_result: result, span: active_span, request: request }, false)
                  when :block
                    Datadog.logger.debug { "WAF: #{result.inspect}" }
                    if active_span
                      active_span.set_tag('appsec.action', 'block')
                      active_span.set_tag('appsec.event', 'true')
                      active_span.set_tag(Datadog::Ext::ManualTracing::TAG_KEEP, true)
                    end
                    record_event({ waf_result: result, span: active_span, request: request }, true)
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
                  #op.publish('request.params', request.params)
                  op.publish('request.headers', {'user-agent' => request.user_agent })
                  #op.publish('request.headers', request.each_header.to_a.to_h)
                  #op.publish('request.referer', request.get_header('HTTP_REFERER'))
                  #op.publish('request.user_agent', request.get_header('HTTP_USER_AGENT'))
                  #op.publish('request.path', request.script_name + request.path)
                  nil
                end

              end

              block
            end

            Patcher.instance_variable_set(:@patched, true)
          end

          def record_event(data, blocked)
            span = data[:span]
            request = data[:request]
            env = Datadog.configuration.env || 'test.lloeki'
            tags = Datadog.configuration.tags

            timestamp = Time.now.utc.iso8601

            tags = [
              "service:#{span.service}",
              "env:#{env}",
              '_dd.appsec.enabled:1',
              '_dd.runtime_family:ruby',
            ]

            request_headers = request.each_header.each_with_object({}) { |(k, v), h| h[k.gsub(/^HTTP_/, '').downcase.gsub('_', '-')] = v if k =~ /^HTTP_/ }
            hostname = Socket.gethostname
            platform = RUBY_PLATFORM
            os_type = case platform
                      when /darwin/ then 'Mac OS X'
                      when /linux/ then 'Linux'
                      when /mingw/ then 'Windows'
                      end

            events = []

            data[:waf_result].data.each do |waf|
              waf['filter'].each do |filter|
                event = {
                  event_id: SecureRandom.uuid,
                  event_type: 'appsec.threat.attack',
                  event_version: '0.1.0',
                  detected_at: timestamp,
                  type: waf['flow'],
                  blocked: blocked,
                  rule: {
                    id: waf['rule'],
                    name: waf['rule'],
                    # set: waf['flow'], TODO: what is this?
                  },
                  rule_match: {
                    operator: filter['operator'],
                    operator_value: filter['operator_value'],
                    parameters: [{
                      name: filter['manifest_key'],
                      value: filter['resolved_value'],
                    }],
                    highlight: [filter['match_status']],
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
                      context_version: "0.1.0"
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
                      #   status: 200, # TODO: requires sending event after request
                        blocked: blocked,
                      #   headers: {}, # TODO: requires sending event after request
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
