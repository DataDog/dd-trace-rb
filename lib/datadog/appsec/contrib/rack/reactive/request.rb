# typed: true

require_relative '../request'

module Datadog
  module AppSec
    module Contrib
      module Rack
        module Reactive
          # Dispatch data from a Rack request to the WAF context
          module Request
            def self.publish(op, request)
              catch(:block) do
                op.publish('request.query', Rack::Request.query(request))
                op.publish('request.headers', Rack::Request.headers(request))
                op.publish('request.uri.raw', Rack::Request.url(request))
                op.publish('request.cookies', Rack::Request.cookies(request))
                # op.publish('request.body.raw', Rack::Request.body(request))
                # TODO: op.publish('request.path_params', { k: v }) # route params only?
                # TODO: op.publish('request.path', request.script_name + request.path) # unused for now

                nil
              end
            end

            # rubocop:disable Metrics/MethodLength
            def self.subscribe(op, waf_context)
              addresses = [
                'request.headers',
                'request.uri.raw',
                'request.query',
                'request.cookies',
                # 'request.body.raw',
                # TODO: 'request.path_params',
              ]

              op.subscribe(*addresses) do |*values|
                Datadog.logger.debug { "reacted to #{addresses.inspect}: #{values.inspect}" }
                headers = values[0]
                headers_no_cookies = headers.dup.tap { |h| h.delete('cookie') }
                uri_raw = values[1]
                query = values[2]
                cookies = values[3]
                # body = values[4]

                waf_args = {
                  'server.request.cookies' => cookies,
                  # 'server.request.body.raw' => body,
                  'server.request.query' => query,
                  'server.request.uri.raw' => uri_raw,
                  'server.request.headers' => headers,
                  'server.request.headers.no_cookies' => headers_no_cookies,
                  # TODO: 'server.request.path_params' => path_params,
                }

                waf_timeout = Datadog::AppSec.settings.waf_timeout
                result = waf_context.run(waf_args, waf_timeout)

                Datadog.logger.debug { "WAF TIMEOUT: #{result.inspect}" } if result.timeout

                case result.status
                when :match
                  Datadog.logger.debug { "WAF: #{result.inspect}" }

                  block = result.actions.include?('block')

                  yield [result, block]

                  throw(:block, [result, true]) if block
                when :ok
                  Datadog.logger.debug { "WAF OK: #{result.inspect}" }
                when :invalid_call
                  Datadog.logger.debug { "WAF CALL ERROR: #{result.inspect}" }
                when :invalid_rule, :invalid_flow, :no_rule
                  Datadog.logger.debug { "WAF RULE ERROR: #{result.inspect}" }
                else
                  Datadog.logger.debug { "WAF UNKNOWN: #{action.inspect} #{result.inspect}" }
                end
              end
            end
            # rubocop:enable Metrics/MethodLength
          end
        end
      end
    end
  end
end
