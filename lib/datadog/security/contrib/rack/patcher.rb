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

          # TODO: logger
          def logger
            return @logger if @logger

            @logger ||= ::Logger.new(STDOUT)
            #@logger.level = ::Logger::DEBUG
            @logger.level = ::Logger::DEBUG
            @logger.debug { 'logger enabled' }
            @logger
          end

          def patch
            Instrumentation.gateway.watch('rack.request') do |request|
              block = false

              Reactive::Operation.new('rack.request') do |op|
                if defined?(Datadog::Tracer) && Datadog.respond_to?(:tracer) && (tracer = Datadog.tracer)
                  root_span = Datadog.tracer.active_root_span
                  active_span = Datadog.tracer.active_span

                  logger.debug { "root span: #{root_span.span_id}"} if root_span
                  logger.debug { "active span: #{active_span.span_id}"} if active_span
                end

                addresses = [
                  'request.user_agent',
                  'request.params',
                  'request.headers',
                  'request.referer',
                  'request.path',
                ]
                op.subscribe(*addresses) do |*values|
                  user_agent = values[0]
                  params = values[1]
                  headers = values[2]
                  referer = values[3]
                  path = values[4]

                  waf_args = Datadog::Security::WAF::Args[
                    '#.filtered_request_params | flat_keys' => params.keys.flatten,
                    '#.filtered_request_params | flat_values' => params.values.flatten,
                    '#.http_headers | flat_keys' => headers.keys.flatten,
                    '#.http_headers | flat_values' => headers.values.flatten,
                    "#.request.env['HTTP_REFERER']" => referer,
                    '#.client_user_agent' => user_agent,
                    '#.request_path' => path,
                  ]
                  #logger.debug { "WAF args:\n" << JSON.pretty_generate(waf_args) }

                  block = Datadog::Security::WAF.run(waf_args)

                  throw(:block, :block) if block
                end

                block = catch(:block) do
                  op.publish('request.params', request.params)
                  op.publish('request.headers', request.each_header.to_a.to_h)
                  op.publish('request.referer', request.get_header('HTTP_REFERER'))
                  op.publish('request.user_agent', request.get_header('HTTP_USER_AGENT'))
                  op.publish('request.path', request.script_name + request.path)
                  nil
                end

                if block && active_span
                  active_span.set_tag('security.blocked', true)
                  active_span.set_tag(Datadog::Ext::ManualTracing::TAG_KEEP, true)
                end
              end

              block
            end

            Patcher.instance_variable_set(:@patched, true)
          end
        end
      end
    end
  end
end
