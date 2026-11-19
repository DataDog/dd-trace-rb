# frozen_string_literal: true

require_relative "events/render_partial"
require_relative "events/render_template"

module Datadog
  module Tracing
    module Contrib
      module ActionView
        # Defines collection of instrumented ActionView events
        module Events
          ALL = [
            Events::RenderPartial,
            Events::RenderTemplate,
          ].freeze

          def self.all
            self::ALL
          end

          def self.subscriptions
            all.collect(&:subscriptions).collect(&:to_a).flatten
          end

          def self.subscribe!
            all.each(&:subscribe!)
          end
        end
      end
    end
  end
end
