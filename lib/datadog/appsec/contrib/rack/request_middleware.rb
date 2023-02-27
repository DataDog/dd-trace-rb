require 'json'

require_relative '../../ext'
require_relative '../../instrumentation/gateway'
require_relative '../../processor'
require_relative '../../response'

require_relative '../../../tracing/client_ip'
require_relative '../../../tracing/contrib/rack/header_collection'

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
          end

          def call(env)
            return @app.call(env) unless Datadog::AppSec.enabled?

            processor = Datadog::AppSec.processor

            return @app.call(env) if processor.nil? || !processor.ready?

            # TODO: handle exceptions, except for @app.call

            context = processor.activate_context
            env['datadog.waf.context'] = context

            request = ::Rack::Request.new(env)

            add_appsec_tags(processor, active_trace, active_span, env)

            request_return, request_response = catch(::Datadog::AppSec::Ext::INTERRUPT) do
              Instrumentation.gateway.push('rack.request', request) do
                @app.call(env)
              end
            end

            if request_response && request_response.any? { |action, _event| action == :block }
              request_return = AppSec::Response.negotiate(env).to_rack
            end

            response = ::Rack::Response.new(request_return[2], request_return[0], request_return[1])
            response.instance_eval do
              @waf_context = context
            end

            _response_return, response_response = Instrumentation.gateway.push('rack.response', response)

            context.events.each do |e|
              e[:response] ||= response
              e[:request]  ||= request
            end

            AppSec::Event.record(*context.events)

            if response_response && response_response.any? { |action, _event| action == :block }
              request_return = AppSec::Response.negotiate(env).to_rack
            end

            request_return
          ensure
            if context
              add_waf_runtime_tags(active_trace, context)
              processor.deactivate_context
            end
          end

          private

          def active_trace
            # TODO: factor out tracing availability detection

            return unless defined?(Datadog::Tracing)

            Datadog::Tracing.active_trace
          end

          def active_span
            # TODO: factor out tracing availability detection

            return unless defined?(Datadog::Tracing)

            Datadog::Tracing.active_span
          end

          def add_appsec_tags(processor, trace, span, env)
            return unless trace

            trace.set_tag('_dd.appsec.enabled', 1)
            trace.set_tag('_dd.runtime_family', 'ruby')
            trace.set_tag('_dd.appsec.waf.version', Datadog::AppSec::WAF::VERSION::BASE_STRING)

            if span && span.get_tag(Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP).nil?
              request_header_collection = Datadog::Tracing::Contrib::Rack::Header::RequestHeaderCollection.new(env)

              # always collect client ip, as this is part of AppSec provided functionality
              Datadog::Tracing::ClientIp.set_client_ip_tag!(
                span,
                headers: request_header_collection,
                remote_ip: env['REMOTE_ADDR']
              )
            end

            if processor.ruleset_info
              trace.set_tag('_dd.appsec.event_rules.version', processor.ruleset_info[:version])

              unless @oneshot_tags_sent
                # Small race condition, but it's inoccuous: worst case the tags
                # are sent a couple of times more than expected
                @oneshot_tags_sent = true

                trace.set_tag('_dd.appsec.event_rules.loaded', processor.ruleset_info[:loaded].to_f)
                trace.set_tag('_dd.appsec.event_rules.error_count', processor.ruleset_info[:failed].to_f)
                trace.set_tag('_dd.appsec.event_rules.errors', JSON.dump(processor.ruleset_info[:errors]))
                trace.set_tag('_dd.appsec.event_rules.addresses', JSON.dump(processor.addresses))

                # Ensure these tags reach the backend
                trace.keep!
                trace.set_tag(
                  Datadog::Tracing::Metadata::Ext::Distributed::TAG_DECISION_MAKER,
                  Datadog::Tracing::Sampling::Ext::Decision::ASM
                )
              end
            end
          end

          def add_waf_runtime_tags(trace, context)
            return unless trace
            return unless context

            trace.set_tag('_dd.appsec.waf.timeouts', context.timeouts)

            # these tags expect time in us
            trace.set_tag('_dd.appsec.waf.duration', context.time_ns / 1000.0)
            trace.set_tag('_dd.appsec.waf.duration_ext', context.time_ext_ns / 1000.0)
          end
        end
      end
    end
  end
end
