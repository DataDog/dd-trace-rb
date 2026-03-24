# frozen_string_literal: true

require 'base64'

require_relative '../../../event'
require_relative '../../../trace_keeper'
require_relative '../../../security_event'
require_relative '../../../instrumentation/gateway'
require_relative '../../../utils/http/media_type'
require_relative '../../../utils/http/body'
require_relative '../../../../core/header_collection'
require_relative '../../../../tracing/client_ip'

module Datadog
  module AppSec
    module Contrib
      module AwsLambda
        module Gateway
          module Watcher
            RequestInfo = Struct.new(:host, :user_agent, :remote_addr, :headers, keyword_init: true)

            class << self
              def watch
                gateway = Instrumentation.gateway

                activate_context(gateway)
                handle_request(gateway)
                handle_response(gateway)
              end

              def activate_context(gateway = Instrumentation.gateway)
                gateway.watch('aws_lambda.request.start') do |stack, event|
                  security_engine = Datadog::AppSec.security_engine

                  if security_engine
                    trace = Datadog::Tracing.active_trace
                    span = Datadog::Tracing.active_span

                    Datadog::AppSec::Context.activate(
                      Datadog::AppSec::Context.new(trace, span, security_engine.new_runner)
                    )

                    span&.set_metric(Datadog::AppSec::Ext::TAG_APPSEC_ENABLED, 1)
                  end

                  stack.call(event)
                end
              end

              def handle_request(gateway = Instrumentation.gateway)
                gateway.watch('aws_lambda.request.start') do |stack, event|
                  context = AppSec::Context.active
                  if context
                    run_request_waf(context, event)
                  end

                  stack.call(event)
                end
              end

              def handle_response(gateway = Instrumentation.gateway)
                gateway.watch('aws_lambda.response.start') do |stack, response|
                  context = AppSec::Context.active
                  if context
                    run_response_waf(context, response)
                    finalize(context)
                  end

                  stack.call(response)
                end
              end

              private

              def run_request_waf(context, event)
                headers = parse_headers(event)
                source_ip = event.dig('requestContext', 'identity', 'sourceIp') ||
                  event.dig('requestContext', 'http', 'sourceIp')

                context.state[:request_info] = RequestInfo.new(
                  host: headers['host'],
                  user_agent: headers['user-agent'],
                  remote_addr: source_ip,
                  headers: headers,
                )

                persistent_data = {
                  'server.request.cookies' => parse_cookies(headers),
                  'server.request.query' => parse_query(event),
                  'server.request.uri.raw' => build_fullpath(event),
                  'server.request.headers' => headers,
                  'server.request.headers.no_cookies' => headers.dup.tap { |h| h.delete('cookie') },
                  'http.client_ip' => extract_client_ip(source_ip, headers),
                  'server.request.method' => extract_method(event),
                  'server.request.body' => parse_body(event, headers),
                  'server.request.path_params' => event['pathParameters'],
                }
                persistent_data.compact!

                result = context.run_waf(persistent_data, {}, Datadog.configuration.appsec.waf_timeout)

                if result.match? || !result.attributes.empty?
                  context.events.push(
                    AppSec::SecurityEvent.new(result, trace: context.trace, span: context.span)
                  )
                end

                if result.match?
                  AppSec::Event.tag(context, result)
                  TraceKeeper.keep!(context.trace) if result.keep?

                  AppSec::ActionsHandler.handle(result.actions)
                end
              end

              def run_response_waf(context, response)
                response = response || {}
                headers = parse_headers(response)

                persistent_data = {
                  'server.response.status' => (response['statusCode'] || 200).to_s,
                  'server.response.headers' => headers,
                  'server.response.headers.no_cookies' => headers.dup.tap { |h| h.delete('set-cookie') },
                }

                result = context.run_waf(persistent_data, {}, Datadog.configuration.appsec.waf_timeout)

                if result.match?
                  AppSec::Event.tag(context, result)
                  TraceKeeper.keep!(context.trace) if result.keep?

                  context.events.push(
                    AppSec::SecurityEvent.new(result, trace: context.trace, span: context.span)
                  )

                  AppSec::ActionsHandler.handle(result.actions)
                end
              end

              def finalize(context)
                AppSec::Event.record(context, request: context.state[:request_info])

                context.export_metrics
                context.export_request_telemetry
              ensure
                Datadog::AppSec::Context.deactivate
              end

              def parse_headers(obj)
                (obj['headers'] || {}).each_with_object({}) do |(key, value), hash|
                  hash[key.downcase] = value
                end
              end

              def parse_cookies(headers)
                cookie_header = headers['cookie']
                return {} unless cookie_header

                cookie_header.split(';').each_with_object({}) do |pair, hash|
                  name, value = pair.strip.split('=', 2)
                  hash[name] = value if name
                end
              end

              def parse_query(event)
                event['multiValueQueryStringParameters'] ||
                  event['queryStringParameters'] ||
                  {}
              end

              def build_fullpath(event)
                path = event['path'] || event['rawPath'] || '/'
                qs = build_query_string(event)
                qs.empty? ? path : "#{path}?#{qs}"
              end

              def build_query_string(event)
                raw = event['rawQueryString']
                return raw if raw && !raw.empty?

                URI.encode_www_form(event.fetch('queryStringParameters', {}))
              end

              def extract_method(event)
                event['httpMethod'] ||
                  event.dig('requestContext', 'http', 'method') ||
                  'GET'
              end

              def extract_client_ip(remote_ip, headers)
                header_collection = Datadog::Core::HeaderCollection.from_hash(headers)
                Datadog::Tracing::ClientIp.extract_client_ip(header_collection, remote_ip)
              end

              def parse_body(event, headers)
                raw = event['body']
                return nil if raw.nil?

                raw = event['isBase64Encoded'] ? Base64.decode64(raw) : raw

                content_type = headers['content-type']
                return nil unless content_type

                media_type = AppSec::Utils::HTTP::MediaType.parse(content_type)
                return nil unless media_type

                AppSec::Utils::HTTP::Body.parse(raw, media_type: media_type)
              end
            end
          end
        end
      end
    end
  end
end
