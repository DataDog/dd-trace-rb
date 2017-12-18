module Datadog
  module Contrib
    module Rack
      # QueueTime simply...
      module QueueTime
        REQUEST_START = 'HTTP_X_REQUEST_START'.freeze

        module_function

        def get_request_start(env, now = Time.now.utc)
          header = env[REQUEST_START]
          return unless header

          # nginx header is in the format "t=1512379167.574"
          # TODO: this should be generic enough to work with any
          # frontend web server or load balancer
          time_string = header.split('t=')[1]
          return if time_string.nil?

          # return the request_start only if it's lesser than
          # current time, to avoid significant clock skew
          request_start = Time.at(time_string.to_f)
          request_start.utc > now ? nil : request_start
        rescue StandardError => e
          # in case of an Exception we don't create a
          # `request.enqueuing` span
          Datadog::Tracer.log.debug("[experimental] unable to parse request enqueuing: #{e}")
          nil
        end
      end
    end
  end
end
