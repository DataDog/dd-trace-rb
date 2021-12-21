# typed: ignore

require 'datadog/security/instrumentation/gateway'
require 'datadog/security/assets'

module Datadog
  module Security
    module Contrib
      module Rack
        # Topmost Rack middleware for Security
        class RequestMiddleware
          def initialize(app, opt = {})
            @app = app

            # TODO: move to integration? (may be too early)
            require_libddwaf

            if libddwaf_required?
              Datadog::Security::WAF.logger = Datadog.logger if Datadog.logger.debug?
              @waf = Datadog::Security::WAF::Handle.new(waf_rules)

              # TODO: check is too low level
              # TODO: use proper exception
              raise if @waf.handle_obj.null?
            end
          end

          def waf_rules
            @waf_rules ||= JSON.parse(Datadog::Security::Assets.waf_rules)
          end

          def call(env)
            return @app.call(env) unless libddwaf_required?

            # TODO: handle exceptions, except for @app.call

            context = Datadog::Security::WAF::Context.new(@waf)
            # TODO: check is too low level
            # TODO: use proper exception
            raise if context.context_obj.null?

            env['datadog.waf.context'] = context
            request = ::Rack::Request.new(env)

            ret, res = Instrumentation.gateway.push('rack.request', request) do
              @app.call(env)
            end

            if res && res.any? { |action, _event| action == :block }
              ret = [403, { 'Content-Type' => 'text/html' }, [Datadog::Security::Assets.blocked]]
            end

            response = ::Rack::Response.new(ret[2], ret[0], ret[1])
            response.instance_eval do
              @waf_context = context
            end

            _, res2 = Instrumentation.gateway.push('rack.response', response)

            res.each { |a, e| [a, e.merge!(response: response)] } if res
            res2.each { |a, e| [a, e.merge!(request: request)] } if res2
            if res2
              if res
                res = res + res2
              else
                res = res2
              end
            end

            if res && res.any?
              Security::Event.record(*res.map { |_action, event| event })
            end

            ret
          end

          def libddwaf_required?
            defined?(Datadog::Security::WAF)
          end

          def require_libddwaf
            require 'libddwaf'
          rescue LoadError => e
            Datadog.logger.warn { "LoadError: libddwaf failed to load: #{e.message}. Try adding `gem 'libddwaf'` to your Gemfile" }
          end
        end
      end
    end
  end
end
