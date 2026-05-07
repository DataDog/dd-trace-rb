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

          def call(env, configuration, &block)
            if (proxy_type = env[Ext::HEADER_X_DD_PROXY])
              return call_with_inferred_proxy(env, proxy_type, &block)
            end

            return yield unless configuration[:request_queuing]

            # parse the request queue time
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
            # finish the `queue` span now to record only the time spent *in queue*,
            # excluding the time spent processing the request itself
            queue_span.finish

            yield
          ensure
            # Ensure that the spans are finished even if an exception is raised.
            # **This is very important** to prevent the trace from leaking between requests,
            # especially because `queue_span` is normally a root span.
            queue_span&.finish
            request_span&.finish
          end

          # Creates a virtual parent span representing the upstream proxy
          # that wraps the actual request processing.
          def call_with_inferred_proxy(env, proxy_type)
            span_name = Ext::PROXY_SPAN_NAMES[proxy_type]
            return yield unless span_name

            path = env[Ext::HEADER_X_DD_PROXY_PATH]
            stage = env[Ext::HEADER_X_DD_PROXY_STAGE]
            domain = env[Ext::HEADER_X_DD_PROXY_DOMAIN_NAME]
            method = env[Ext::HEADER_X_DD_PROXY_HTTPMETHOD]
            resource_path = env[Ext::HEADER_X_DD_PROXY_RESOURCE_PATH]
            request_time_ms = env[Ext::HEADER_X_DD_PROXY_REQUEST_TIME_MS]

            # NOTE: resource_path is the parameterized route (e.g. /users/{id}) vs literal path
            route = resource_path
            resource = "#{method} #{route || path}" if method

            options = { service: domain, type: Tracing::Metadata::Ext::AppTypes::TYPE_WEB }
            options[:start_time] = Time.at(request_time_ms.to_f / 1000) if request_time_ms

            inferred_span = Tracing.trace(span_name, **options)
            inferred_span.resource = resource if resource
            inferred_span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, proxy_type)
            inferred_span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_SERVER)
            inferred_span.set_tag('stage', stage) if stage
            inferred_span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_METHOD, method) if method
            inferred_span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_URL, "https://#{domain}#{path}") if domain && path
            inferred_span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_ROUTE, route) if route
            inferred_span.set_metric(Ext::TAG_INFERRED_SPAN, 1)

            set_optional_tags(inferred_span, env: env, proxy_type: proxy_type)

            yield
          ensure
            if inferred_span
              Tracing.active_trace&.resource = resource if resource
              propagate_request_span_tags(inferred_span, env: env)

              inferred_span.finish
            end
          end

          # Sets cloud provider metadata and constructs the resource ARN.
          def set_optional_tags(span, env:, proxy_type:)
            account_id = env[Ext::HEADER_X_DD_PROXY_ACCOUNT_ID]
            api_id = env[Ext::HEADER_X_DD_PROXY_API_ID]
            region = env[Ext::HEADER_X_DD_PROXY_REGION]
            user = env[Ext::HEADER_X_DD_PROXY_USER]

            # API Gateway v1 sends region as a single-quoted string
            region = region.delete("'") if region

            span.set_tag('account_id', account_id) if account_id
            span.set_tag('apiid', api_id) if api_id
            span.set_tag('region', region) if region
            span.set_tag('aws_user', user) if user

            if api_id && region
              restapi_prefix = proxy_type == Ext::PROXY_AWS_APIGATEWAY ? 'restapis' : 'apis'
              span.set_tag('dd_resource_key', "arn:aws:apigateway:#{region}::/#{restapi_prefix}/#{api_id}")
            end
          end

          # Propagates response-level and security tags from the request span to
          # the inferred parent.
          def propagate_request_span_tags(span, env:)
            rack_span = env[Ext::RACK_ENV_REQUEST_SPAN]
            return unless rack_span

            if (status_code = rack_span.get_tag(Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE))
              span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE, status_code)
              span.status = Tracing::Metadata::Ext::Errors::STATUS if status_code.to_i >= 500
            end

            if (user_agent = rack_span.get_tag(Tracing::Metadata::Ext::HTTP::TAG_USER_AGENT))
              span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_USER_AGENT, user_agent)
            end

            # NOTE: Tracing shouldn't know about AppSec tags.
            if (appsec_enabled = rack_span.get_metric('_dd.appsec.enabled'))
              span.set_metric('_dd.appsec.enabled', appsec_enabled)
            end

            # NOTE: Tracing shouldn't know about AppSec tags.
            if (appsec_json = rack_span.get_tag('_dd.appsec.json'))
              span.set_tag('_dd.appsec.json', appsec_json)
            end
          end
        end
      end
    end
  end
end
