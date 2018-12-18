module Datadog
  module Contrib
    module Rack
      # QueueTime simply...
      module QueueTime
        REQUEST_START = 'HTTP_X_REQUEST_START'.freeze
        QUEUE_START = 'HTTP_X_QUEUE_START'.freeze

        module_function

        def get_request_start(env, now = Time.now.utc)
          header = env[REQUEST_START] || env[QUEUE_START]
          return unless header

          # nginx header is in the format "t=1512379167.574"
          # TODO: this should be generic enough to work with any
          # frontend web server or load balancer
          time_string = header.split('t=')[1]
          return if time_string.nil?

          # Return nil if the time is clearly invalid
          time_value = time_string.to_f
          return if time_value.zero?

          # return the request_start only if it's lesser than
          # current time, to avoid significant clock skew
          request_start = Time.at(time_value)
          request_start.utc > now ? nil : request_start
        rescue StandardError => e
          # in case of an Exception we don't create a
          # `request.queuing` span
          Datadog::Tracer.log.debug("[rack] unable to parse request queue headers: #{e}")
          nil
        end
      end
    end
  end
end
