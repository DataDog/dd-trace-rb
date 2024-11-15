# frozen_string_literal: true

require_relative '../../ext'
require_relative '../../event'

require 'byebug'

module Datadog
  module Tracing
    module Contrib
      module Karafka
        module Events
          module Error
            module Occur
              include Karafka::Event

              def self.subscribe!
                ::Karafka.monitor.subscribe 'error.consume' do |event|
                end
              end
            end
          end
        end
      end
    end
  end
end

