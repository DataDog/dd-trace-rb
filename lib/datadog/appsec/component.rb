# frozen_string_literal: true

require_relative 'processor'

module Datadog
  module AppSec
    # Core-pluggable component for AppSec
    class Component
      class << self
        def build_appsec_component(settings)
          return unless settings.enabled

          processor = create_processor
          new(processor: processor)
        end

        private

        def create_processor
          processor = Processor.new
          return nil unless processor.ready?

          processor
        end
      end

      attr_reader :processor

      def initialize(processor:)
        @processor = processor
      end

      def shutdown!
        if processor && processor.ready?
          processor.finalize
          @processor = nil
        end
      end
    end
  end
end
