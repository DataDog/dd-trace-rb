# typed: true
require 'datadog/tracing/contrib/patcher'
require 'datadog/tracing/contrib/action_mailer/ext'
require 'datadog/tracing/contrib/action_mailer/events'

module Datadog
  module Tracing
    module Contrib
      module ActionMailer
        # Patcher enables patching of 'action_mailer' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            # Subscribe to ActionMailer events
            Events.subscribe!
          end
        end
      end
    end
  end
end
