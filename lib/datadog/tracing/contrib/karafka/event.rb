# frozen_string_literal: true

require_relative '../analytics'
require_relative 'ext'

module Datadog
  module Tracing
    module Contrib
      module Karafka
        module Event
          def self.included(base)
            base.extend(ClassMethods)
          end

          module ClassMethods
            def span_options
              { service: configuration[:service_name] }
            end

            def configuration
              Datadog.configuration.tracing[:karafka]
            end
          end
        end
      end
    end
  end
end
