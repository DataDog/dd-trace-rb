# typed: true
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
