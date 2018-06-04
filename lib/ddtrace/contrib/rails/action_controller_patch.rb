module Datadog
  module Contrib
    module Rails
      # Instrument ActiveController processing
      module ActionControllerPatch
        def self.included(base)
          if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.0.0')
            base.send(:prepend, ProcessActionPatch)
          else
            base.class_eval do
              alias_method :process_action_without_datadog, :process_action

              include ProcessActionPatch
            end
          end
        end

        # Compatibility module for Ruby versions not supporting #prepend
        module ProcessActionCompatibilityPatch
          def process_action(*args)
            process_action_without_datadog(*args)
          end
        end

        # ActionController patch
        module ProcessActionPatch
          # compatibility module for Ruby versions not supporting #prepend
          include ProcessActionCompatibilityPatch unless Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.0.0')

          def process_action(*args)
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
              payload[:status] = response.status
              result
            rescue Exception => e
              payload[:exception] = [e.class.name, e.message]
              payload[:exception_object] = e
              raise e
            end
          ensure
            Datadog::Contrib::Rails::ActionController.finish_processing(payload)
          end
        end
      end
    end
  end
end
