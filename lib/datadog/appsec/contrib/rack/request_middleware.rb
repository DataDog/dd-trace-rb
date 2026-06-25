# frozen_string_literal: true

require 'json'

require_relative 'response_body'
require_relative 'gateway/request'
require_relative 'gateway/response'

require_relative '../../event'
require_relative '../../response'
require_relative '../../api_security'
require_relative '../../default_header_tags'
require_relative '../../route_normalizer'
require_relative '../../security_event'
require_relative '../../instrumentation/gateway'

require_relative '../../../core/header_collection'
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

          # rubocop:disable Metrics/MethodLength
          def call(env)
            return @app.call(env) unless Datadog::AppSec.enabled?

            boot = Datadog::Core::Remote::Tie.boot
            Datadog::Core::Remote::Tie::Tracing.tag(boot, active_span)

            # For a given request, keep using the first Rack stack scope for
            # nested apps. Don't set `context` local variable so that on popping
            # out of this nested stack we don't finalize the parent's context
            return @app.call(env) if active_context(env)

            security_engine = Datadog::AppSec.security_engine

            # TODO: handle exceptions, except for @app.call
            return @app.call(env) unless security_engine

            ctx = Datadog::AppSec::Context.activate(
              Datadog::AppSec::Context.new(active_trace, active_span, security_engine.new_runner)
            )
            env[Datadog::AppSec::Ext::CONTEXT_KEY] = ctx

            add_appsec_tags(ctx)
            add_request_tags(ctx, env)

            http_response = nil
            gateway_request = Gateway::Request.new(env)
            gateway_response = nil

            interrupt_params = catch(::Datadog::AppSec::Ext::INTERRUPT) do
              # TODO: This event should be renamed into `rack.request.start` to
              #       reflect that it's the beginning of the request-cycle
              http_response, _gateway_request = Instrumentation.gateway.push('rack.request', gateway_request) do
                @app.call(env)
              end

              gateway_response = Gateway::Response.new(
                http_response[2], http_response[0], http_response[1], context: ctx
              )

              Instrumentation.gateway.push('rack.request.finish', gateway_request)
              Instrumentation.gateway.push('rack.response', gateway_response)

              nil
            end

            add_normalized_route_tag(ctx, env)

            if interrupt_params
              ctx.mark_as_interrupted!
              http_response = AppSec::Response.from_interrupt_params(interrupt_params, env['HTTP_ACCEPT']).to_rack
            end

            # NOTE: This is not optimal, but in the current implementation
            #       `gateway_response` is a container to dispatch response event
            #       and in case of interruption it suppose to be `nil`.
            #
            #       `http_response` is a real response object in both cases, but
            #       to save us some computations, we will use already pre-computed
            #       `gateway_response` instead of re-creating it.
            #
            # WARNING: This part will be refactored.
            tmp_response = if interrupt_params
              Gateway::Response.new(http_response[2], http_response[0], http_response[1], context: ctx)
            else
              gateway_response
            end

            if AppSec::APISecurity.enabled? && AppSec::APISecurity.sample_trace?(ctx.trace) &&
                AppSec::APISecurity.sample?(gateway_request.request, tmp_response.response)
              ctx.extract_schema!
            end

            AppSec::Event.record(ctx, request: gateway_request)

            add_response_tags(ctx, tmp_response)
            http_response
          ensure
            if ctx
              ctx.export_metrics
              ctx.export_request_telemetry

              Datadog::AppSec::Context.deactivate
            end
          end
          # rubocop:enable Metrics/MethodLength

          private

          def active_context(env)
            env[Datadog::AppSec::Ext::CONTEXT_KEY]
          end

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

          # standard:disable Metrics/MethodLength
          def add_appsec_tags(context)
            span = context.span
            trace = context.trace

            return unless trace && span

            span.set_metric(Datadog::AppSec::Ext::TAG_APPSEC_ENABLED, 1)
            span.set_tag('_dd.runtime_family', 'ruby')
            span.set_tag('_dd.appsec.waf.version', Datadog::AppSec::WAF::VERSION::BASE_STRING)

            if context.waf_runner_ruleset_version
              span.set_tag('_dd.appsec.event_rules.version', context.waf_runner_ruleset_version)

              unless oneshot_tags_sent?
                # Small race condition, but it's inoccuous: worst case the tags
                # are sent a couple of times more than expected
                @oneshot_tags_sent = true

                span.set_tag('_dd.appsec.event_rules.addresses', JSON.dump(context.waf_runner_known_addresses))

                # Ensure these tags reach the backend
                trace.keep!
                trace.set_tag(
                  Datadog::Tracing::Metadata::Ext::Distributed::TAG_DECISION_MAKER,
                  Datadog::Tracing::Sampling::Ext::Decision::ASM
                )
              end
            end
          end
          # standard:enable Metrics/MethodLength

          def add_request_tags(context, env)
            span = context.span
            return unless span

            headers = Tracing::Contrib::Rack::Header::RequestHeaderCollection.new(env)
            AppSec::DefaultHeaderTags.tag_request(span, headers)

            if span.get_tag(Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP).nil?
              # always collect client ip, as this is part of AppSec provided functionality
              Datadog::Tracing::ClientIp.set_client_ip_tag!(
                span, headers: headers, remote_ip: env['REMOTE_ADDR']
              )
            end
          end

          def add_response_tags(context, response)
            span = context.span
            return unless span

            AppSec::DefaultHeaderTags.tag_response(
              span, Datadog::Core::HeaderCollection.from_hash(response.headers)
            )

            unless response.headers.key?('content-length')
              length = ResponseBody.content_length(response.body)
              span.set_tag('http.response.headers.content-length', length.to_s) if length
            end
          end

          def add_normalized_route_tag(context, env)
            return unless AppSec::APISecurity.enabled?

            span = context.span
            return unless span

            pattern = context.trace&.get_tag(Tracing::Metadata::Ext::HTTP::TAG_ROUTE)
            return unless pattern

            # NOTE: To build full path that covers mounted engines we need to add
            #       pre-computed by Tracer route path tag to the normalized route
            prefix = context.trace&.get_tag(Tracing::Metadata::Ext::HTTP::TAG_ROUTE_PATH) || env['SCRIPT_NAME']
            normalized_route = RouteNormalizer.extract_normalized_route(env, prefix: prefix, pattern: pattern)
            return unless normalized_route

            span.set_tag(AppSec::Ext::TAG_NORMALIZED_ROUTE, "#{prefix}#{normalized_route}")
          end

          def oneshot_tags_sent?
            @oneshot_tags_sent
          end
        end
      end
    end
  end
end
