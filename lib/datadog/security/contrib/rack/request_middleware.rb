require 'datadog/security/instrumentation/gateway'

require 'libddwaf'
require 'datadog/security/assets'
require 'datadog/security/reactive/operation'

module Datadog
  module Security
    module Contrib
      module Rack
        class RequestMiddleware
          def initialize(app, opt = {})
            @app = app
            Datadog::Security::WAF.logger = Datadog.logger if Datadog.logger.debug?
            @waf = Datadog::Security::WAF::Handle.new(waf_rules)
            fail if @waf.handle_obj.null?
          end

          def waf_rules
            JSON.parse(Datadog::Security::Assets.waf_rules)
          end

          def call(env)
            context = Datadog::Security::WAF::Context.new(@waf)
            fail if context.context_obj.null?
            env['datadog.waf.context'] = context
            request = ::Rack::Request.new(env)

            block = Instrumentation.gateway.push('rack.request', request)

            block ? [403, { 'Content-Type' => 'text/html' }, [Datadog::Security::Assets.blocked]] : @app.call(env)
          end
        end
      end
    end
  end
end
