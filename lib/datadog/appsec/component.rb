# frozen_string_literal: true

require_relative 'processor'
require_relative 'transport/http'

module Datadog
  module AppSec
    # Core-pluggable component for AppSec
    class Component
      class << self
        def build_appsec_component(settings, agent_settings)
          return unless settings.enabled

          processor = create_processor
          new(agent_settings, processor: processor)
        end

        private

        def create_processor
          processor = Processor.new
          return nil unless processor.ready?

          processor
        end
      end

      attr_reader :processor, :transport

      def initialize(agent_settings, processor:)
        @processor = processor
        transport_options = {}
        transport_options[:agent_settings] = agent_settings if agent_settings

        @transport = Transport::HTTP.default(**transport_options)
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
