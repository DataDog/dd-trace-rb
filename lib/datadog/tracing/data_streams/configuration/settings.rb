# frozen_string_literal: true

require_relative '../processor'

module Datadog
  module Tracing
    module Contrib
      module DataStreams
        module Configuration
          # Custom settings for the Data Streams component
          class Settings
            def initialize
              @processor = Processor.new
            end

            attr_reader :processor
          end
        end
      end
    end
  end
end
