require 'ddtrace/contrib/patching/base'

module Datadog
  module Contrib
    module Rails
      # Instrument ActiveController processing
      module ActionControllerPatch
        extend Datadog::Contrib::Patching::Base

        datadog_patch_method(:process_action) do |*args|
          begin
            # mutable payload with a tracing context that is used in two different
            # signals; it propagates the request span so that it can be finished
            # no matter what
            payload = {
              controller: self.class,
              action: action_name,
              headers: {
                # The exception this controller was given in the request,
                # which is typical if the controller is configured to handle exceptions.
                request_exception: request.headers['action_dispatch.exception']
              },
              tracing_context: {}
            }

            begin
              # process and catch request exceptions
              Datadog::Contrib::Rails::ActionController.start_processing(payload)
              result = super(*args)
              status = datadog_response_status
              payload[:status] = status unless status.nil?
              result
            # rubocop:disable Lint/RescueException
            rescue Exception => e
              payload[:exception] = [e.class.name, e.message]
              payload[:exception_object] = e
              raise e
            end
          # rubocop:enable Lint/RescueException
          ensure
            Datadog::Contrib::Rails::ActionController.finish_processing(payload)
          end
        end

        def datadog_response_status
          case response
          when ActionDispatch::Response
            response.status
          when Array
            # Likely a Rack response array: first element is the status.
            status = response.first
            status.class <= Integer ? status : nil
          end
        end
      end
    end
  end
end
