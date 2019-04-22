require 'ddtrace/contrib/patcher'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/action_mailer/ext'
require 'ddtrace/contrib/action_mailer/events'

module Datadog
  module Contrib
    module ActionMailer
      # Patcher enables patching of 'action_mailer' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:action_mailer)
        end

        def patch
          do_once(:action_mailer) do
            begin
              # Subscribe to ActionMailer events
              Events.subscribe!

              # Set service info
              configuration = Datadog.configuration[:action_mailer]
              configuration[:tracer].set_service_info(
                configuration[:service_name],
                Ext::APP,
                Datadog::Ext::AppTypes::WORKER
              )
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply ActionMailer integration: #{e}")
            end
          end
        end
      end
    end
  end
end
