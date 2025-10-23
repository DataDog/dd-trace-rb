# frozen_string_literal: true

require_relative 'open_feature/extensions'

module Datadog
  module OpenFeature
    Extensions.activate!

    class << self
      def enabled?
        Datadog.configuration.open_fetaure.enabled
      end

      def evaluator
        component&.evaluator
      end

      private

      def component
        Datadog.send(:components).open_feature
      end
    end
  end
end
