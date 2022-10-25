# typed: ignore

require 'json'

require_relative '../../instrumentation/gateway'
require_relative '../../processor'
require_relative '../../assets'

module Datadog
  module AppSec
    module Contrib
      module Rack
        # Topmost Rack middleware for AppSec
        # This should be inserted just below Datadog::Tracing::Contrib::Rack::TraceMiddleware
        class RequestMiddleware
          def initialize(app, opt = {})
            @app = app

            @oneshot_tags_sent = false
            @processor = Datadog::AppSec::Processor.new
          end

          def call(env)
            return @app.call(env) unless @processor.ready?

            # TODO: handle exceptions, except for @app.call

            context = @processor.new_context

            env['datadog.waf.context'] = context
            request = ::Rack::Request.new(env)

            add_appsec_tags

            request_return, request_response = Instrumentation.gateway.push('rack.request', request) do
              @app.call(env)
            end

            if request_response && request_response.any? { |action, _event| action == :block }
              request_return = [403, { 'Content-Type' => 'text/html' }, [Datadog::AppSec::Assets.blocked]]
            end

            response = ::Rack::Response.new(request_return[2], request_return[0], request_return[1])
            response.instance_eval do
              @waf_context = context
            end

            _response_return, _response_response = Instrumentation.gateway.push('rack.response', response)

            context.events.each do |e|
              e[:response] ||= response
              e[:request]  ||= request
            end

            AppSec::Event.record(*context.events)

            request_return
          ensure
            add_waf_runtime_tags(context) if context
          end

          private

          def active_trace
            # TODO: factor out tracing availability detection

            return unless defined?(Datadog::Tracing)

            Datadog::Tracing.active_trace
          end

          def add_appsec_tags
            return unless active_trace

            active_trace.set_tag('_dd.appsec.enabled', 1)
            active_trace.set_tag('_dd.runtime_family', 'ruby')
            active_trace.set_tag('_dd.appsec.waf.version', Datadog::AppSec::WAF::VERSION::BASE_STRING)

            if @processor.ruleset_info
              active_trace.set_tag('_dd.appsec.event_rules.version', @processor.ruleset_info[:version])

              unless @oneshot_tags_sent
                # Small race condition, but it's inoccuous: worst case the tags
                # are sent a couple of times more than expected
                @oneshot_tags_sent = true

                active_trace.set_tag('_dd.appsec.event_rules.loaded', @processor.ruleset_info[:loaded].to_f)
                active_trace.set_tag('_dd.appsec.event_rules.error_count', @processor.ruleset_info[:failed].to_f)
                active_trace.set_tag('_dd.appsec.event_rules.errors', JSON.dump(@processor.ruleset_info[:errors]))
                active_trace.set_tag('_dd.appsec.event_rules.addresses', JSON.dump(@processor.addresses))

                # Ensure these tags reach the backend
                active_trace.keep!
                trace.set_tag(
                  Datadog::Tracing::Metadata::Ext::Distributed::TAG_DECISION_MAKER,
                  Datadog::Tracing::Sampling::Ext::Decision::ASM
                )
              end
            end
          end

          def add_waf_runtime_tags(context)
            return unless active_trace
            return unless context

            active_trace.set_tag('_dd.appsec.waf.timeouts', context.timeouts)

            # these tags expect time in us
            active_trace.set_tag('_dd.appsec.waf.duration', context.time_ns / 1000.0)
            active_trace.set_tag('_dd.appsec.waf.duration_ext', context.time_ext_ns / 1000.0)
          end
        end
      end
    end
  end
end
