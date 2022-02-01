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

            libddwaf_spec = Gem.loaded_specs['libddwaf']
            libddwaf_platform = libddwaf_spec ? libddwaf_spec.platform.to_s : 'unknown'
            ruby_platforms = Gem.platforms.map(&:to_s)

            if libddwaf_required?
              Datadog.logger.debug { "libddwaf platform: #{libddwaf_platform}" }
              Datadog::Security::WAF.logger = Datadog.logger if Datadog.logger.debug? && Datadog::Security.settings.waf_debug
              @waf = Datadog::Security::WAF::Handle.new(waf_rules)
            else
              Datadog.logger.warn { "libddwaf is missing components. installed platform: #{libddwaf_platform} ruby platforms: #{ruby_platforms}" }
              Datadog.logger.warn { 'AppSec is disabled' }
            end
          end

          def waf_rules
            ruleset_setting = Datadog::Security.settings.ruleset
            case ruleset_setting
            when :recommended, :risky, :strict
              @waf_rules ||= JSON.parse(Datadog::Security::Assets.waf_rules(ruleset_setting))
            when String
              # TODO: handle file missing
              filename = ruleset_setting
              ruleset = File.read(filename)
              @waf_rules ||= JSON.parse(ruleset)
            else
              # TODO: use a proper exception class
              raise "unsupported value for :ruleset: #{ruleset_setting.inspect}"
            end
          end

          def call(env)
            return @app.call(env) unless libddwaf_required?

            # TODO: handle exceptions, except for @app.call

            context = Datadog::Security::WAF::Context.new(@waf)

            env['datadog.waf.context'] = context
            request = ::Rack::Request.new(env)

            request_return, request_response = Instrumentation.gateway.push('rack.request', request) do
              @app.call(env)
            end

            if request_response && request_response.any? { |action, _event| action == :block }
              request_return = [403, { 'Content-Type' => 'text/html' }, [Datadog::Security::Assets.blocked]]
            end

            response = ::Rack::Response.new(request_return[2], request_return[0], request_return[1])
            response.instance_eval do
              @waf_context = context
            end

            _, response_response = Instrumentation.gateway.push('rack.response', response)

            request_response.each { |_, e| e.merge!(response: response) } if request_response
            response_response.each { |_, e| e.merge!(request: request) } if response_response
            both_response = (request_response || []) + (response_response || [])

            if both_response.any?
              Security::Event.record(*both_response.map { |_action, event| event })
            end

            request_return
          end

          def libddwaf_required?
            defined?(Datadog::Security::WAF)
          end

          def require_libddwaf
            require 'libddwaf'
          rescue LoadError => e
            Datadog.logger.warn { "LoadError: libddwaf failed to load: #{e.message}. Try adding `gem 'libddwaf'` to your Gemfile" }
            Datadog.logger.warn { 'Appsec is disabled' }
          end
        end
      end
    end
  end
end
