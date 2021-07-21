require 'datadog/security/instrumentation/gateway'

require 'datadog/security/waf'
require 'datadog/security/reactive/operation'

module Datadog
  module Security
    module Contrib
      module Rack
        class RequestMiddleware
          def initialize(app, opt = {})
            @logger = ::Logger.new(STDOUT)
            #@logger.level = ::Logger::DEBUG
            @logger.level = ::Logger::DEBUG
            @logger.debug { 'logger enabled' }
            @app = app
            Datadog::Security::WAF.load_rules
          end

          # TODO: logger
          attr_reader :logger

          def call(env)
            request = ::Rack::Request.new(env)

            block = Instrumentation.gateway.push('rack.request', request)

            block ? [403, { 'Content-Type' => 'text/html' }, [Assets.blocked]] : @app.call(env)
          end
        end
      end
    end
  end
end
