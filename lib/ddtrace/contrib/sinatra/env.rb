require 'ddtrace/ext/http'
require 'ddtrace/contrib/sinatra/ext'

module Datadog
  module Contrib
    module Sinatra
      # Gets and sets trace information from a Rack Env
      module Env
        module_function

        def datadog_span(env, app)
          env[Ext::RACK_ENV_REQUEST_SPAN][app]
        end

        def set_datadog_span(env, app, span)
          hash = (env[Ext::RACK_ENV_REQUEST_SPAN] ||= {})
          hash[app] = span
        end

        def request_header_tags(env, headers)
          headers ||= []

          {}.tap do |result|
            headers.each do |header|
              rack_header = header_to_rack_header(header)
              if env.key?(rack_header)
                result[Datadog::Ext::HTTP::RequestHeaders.to_tag(header)] = env[rack_header]
              end
            end
          end
        end

        def header_to_rack_header(name)
          "HTTP_#{name.to_s.upcase.gsub(/[-\s]/, '_')}"
        end

        # Was a Sinatra already traced in this request?
        # We don't want to create spans for intermediate Sinatra
        # middlewares that don't match the request at hand.
        def middleware_traced?(env)
          env[Ext::RACK_ENV_MIDDLEWARE_TRACED]
        end

        def set_middleware_traced(env, bool)
          env[Ext::RACK_ENV_MIDDLEWARE_TRACED] = bool
        end

        # The start time of the top-most Sinatra middleware.
        def middleware_start_time(env)
          env[Ext::RACK_ENV_MIDDLEWARE_START_TIME]
        end

        def set_middleware_start_time(env, time = Time.now.utc)
          env[Ext::RACK_ENV_MIDDLEWARE_START_TIME] = time
        end
      end
    end
  end
end
