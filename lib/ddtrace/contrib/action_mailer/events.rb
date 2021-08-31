# typed: false
require 'ddtrace/contrib/action_mailer/events/process'
require 'ddtrace/contrib/action_mailer/events/deliver'

module Datadog
  module Contrib
    module ActionMailer
      # Defines collection of instrumented ActionMailer events
      module Events
        ALL = [
          Events::Process,
          Events::Deliver
        ].freeze

        module_function

        def all
          self::ALL
        end

        def subscriptions
          all.collect(&:subscriptions).collect(&:to_a).flatten
        end

        def subscribe!
          all.each(&:subscribe!)
        end
      end
    end
  end
end
