# frozen_string_literal: true

module Datadog
  module Core
    module Remote
      # Repository update dispatcher
      class Dispatcher
        attr_reader :receivers

        def initialize
          @receivers = []
        end

        def dispatch(changes, repository)
          receivers.each do |receiver|
            matching_changes = changes.select { |c| receiver.match?(c.path) }

            receiver.call(repository, matching_changes) if matching_changes.any?
          end
        end

        class Receiver
          def initialize(matcher, &block)
            @block = block
            @matcher = matcher
          end

          def match?(path)
            @matcher.match?(path)
          end

          def call(repository, changes)
            @block.call(repository, changes)
          end
        end

        class Matcher
          def initialize(&block)
            @block = block
          end

          def match?(path)
            @block.call(path)
          end

          class Product < Matcher
            def initialize(products)
              block = -> (path) { products.include?(path.product) }
              super(&block)
            end
          end
        end
      end
    end
  end
end
