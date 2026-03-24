# frozen_string_literal: true

require_relative '../../metadata/ext'
require_relative '../analytics'
require_relative 'ext'
require_relative 'request_queue'

module Datadog
  module Tracing
    module Contrib
      module Rack
        # Module to create virtual proxy span
        module TraceProxyMiddleware
          module_function

          def call(env, configuration)
            proxy_type = env[Ext::HEADER_X_DD_PROXY]
            return call_with_inferred_proxy(env, proxy_type) { yield } if proxy_type

            return yield unless configuration[:request_queuing]

            start_time = Contrib::Rack::QueueTime.get_request_start(env)
            return yield unless start_time

            options = {
              service: configuration[:web_service_name],
              start_time: start_time,
              type: Tracing::Metadata::Ext::HTTP::TYPE_PROXY
            }

            request_span = Tracing.trace(Ext::SPAN_HTTP_PROXY_REQUEST, **options)

            request_span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT_HTTP_PROXY)
            request_span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_HTTP_PROXY_REQUEST)
            request_span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_PROXY)

            queue_span = Tracing.trace(Ext::SPAN_HTTP_PROXY_QUEUE, **options)

            queue_span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT_HTTP_PROXY)
            queue_span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_HTTP_PROXY_QUEUE)
            queue_span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_PROXY)

            Contrib::Analytics.set_measured(queue_span)
            queue_span.finish

            yield
          ensure
            queue_span&.finish
            request_span&.finish
          end

          def call_with_inferred_proxy(env, proxy_type)
            span_name = Ext::PROXY_SPAN_NAMES[proxy_type]
            return yield unless span_name

            domain = env[Ext::HEADER_X_DD_PROXY_DOMAIN_NAME]
            path = env[Ext::HEADER_X_DD_PROXY_PATH]
            resource_path = env[Ext::HEADER_X_DD_PROXY_RESOURCE_PATH]
            method = env[Ext::HEADER_X_DD_PROXY_HTTPMETHOD]
            stage = env[Ext::HEADER_X_DD_PROXY_STAGE]
            request_time_ms = env[Ext::HEADER_X_DD_PROXY_REQUEST_TIME_MS]

            start_time = Time.at(request_time_ms.to_f / 1000) if request_time_ms

            route = resource_path
            resource = "#{method} #{route || path}"

            options = {
              service: domain,
              start_time: start_time,
              type: Tracing::Metadata::Ext::AppTypes::TYPE_WEB,
            }

            inferred_span = Tracing.trace(span_name, **options)
            inferred_span.resource = resource
            inferred_span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, proxy_type)
            inferred_span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_SERVER)
            inferred_span.set_tag('stage', stage) if stage
            inferred_span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_METHOD, method) if method
            inferred_span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_URL, "https://#{domain}#{path}") if domain && path
            inferred_span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_ROUTE, route) if route
            inferred_span.set_metric(Ext::TAG_INFERRED_SPAN, 1)

            set_optional_tags(env, inferred_span, proxy_type)

            yield
          ensure
            if inferred_span
              inferred_span.resource = resource
              Tracing.active_trace&.resource = resource
              propagate_tags_from_request_span(env, inferred_span)
              inferred_span.finish
            end
          end

          def set_optional_tags(env, span, proxy_type)
            account_id = env[Ext::HEADER_X_DD_PROXY_ACCOUNT_ID]
            api_id = env[Ext::HEADER_X_DD_PROXY_API_ID]
            region = env[Ext::HEADER_X_DD_PROXY_REGION]
            user = env[Ext::HEADER_X_DD_PROXY_USER]

            span.set_tag('account_id', account_id) if account_id
            span.set_tag('apiid', api_id) if api_id
            span.set_tag('region', region) if region
            span.set_tag('aws_user', user) if user

            if api_id && region
              restapi_prefix = (proxy_type == Ext::PROXY_AWS_APIGATEWAY) ? 'restapis' : 'apis'
              span.set_tag('dd_resource_key', "arn:aws:apigateway:#{region}::/#{restapi_prefix}/#{api_id}")
            end
          end

          def propagate_tags_from_request_span(env, inferred_span)
            rack_span = env[Ext::RACK_ENV_REQUEST_SPAN]
            return unless rack_span

            status_code = rack_span.get_tag(Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)
            if status_code
              inferred_span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE, status_code)
              inferred_span.status = Tracing::Metadata::Ext::Errors::STATUS if status_code.to_i >= 500
            end

            user_agent = rack_span.get_tag(Tracing::Metadata::Ext::HTTP::TAG_USER_AGENT)
            inferred_span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_USER_AGENT, user_agent) if user_agent

            appsec_enabled = rack_span.get_metric(AppSec::Ext::TAG_APPSEC_ENABLED)
            inferred_span.set_metric(AppSec::Ext::TAG_APPSEC_ENABLED, appsec_enabled) if appsec_enabled

            appsec_json = rack_span.get_tag('_dd.appsec.json')
            inferred_span.set_tag('_dd.appsec.json', appsec_json) if appsec_json
          end
        end
      end
    end
  end
end
