module Datadog
  module Contrib
    module QueueTime
      REQUEST_START = 'HTTP_X_REQUEST_START'.freeze

      module_function

      def get_request_start(headers, now)
        header = headers[REQUEST_START]
        if header
          # nginx header is in the format "t=1512379167.574"
          time_string = header.split("t=")[1]
          Time.at(time_string.to_f)
        else
          now
        end
      rescue
        # by default return the starting time
        now
      end
    end
  end
end
