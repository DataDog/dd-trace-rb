# typed: ignore

require 'datadog/security/instrumentation/gateway'

require 'datadog/security/assets'
require 'datadog/security/reactive/operation'

module Datadog
  module Security
    module Contrib
      module Rack
        # Topmost Rack middleware for Security
        class RequestMiddleware
          def initialize(app, opt = {})
            @app = app

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

            context = Datadog::Security::WAF::Context.new(@waf)
            # TODO: check is too low level
            # TODO: use proper exception
            raise if context.context_obj.null?

            env['datadog.waf.context'] = context
            env['datadog.waf.rules'] = waf_rules
            request = ::Rack::Request.new(env)

            block = Instrumentation.gateway.push('rack.request', request)

            block ? [403, { 'Content-Type' => 'text/html' }, [Datadog::Security::Assets.blocked]] : @app.call(env)
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
