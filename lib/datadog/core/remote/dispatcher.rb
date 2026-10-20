# frozen_string_literal: true

module Datadog
  module Core
    module Remote
      # Repository update dispatcher
      class Dispatcher
        def initialize(receivers)
          @receivers = receivers.dup
          @mutex = Mutex.new
        end

        def receivers
          @mutex.synchronize { @receivers.dup }
        end

        def add_receivers(*receivers)
          @mutex.synchronize do
            receivers.each { |receiver| @receivers << receiver unless @receivers.include?(receiver) }
          end
          nil
        end

        def dispatch(changes, repository)
          receivers.each do |receiver|
            matching = matching_changes(changes, receiver)

            receiver.call(repository, matching) if matching.any?
          end
        end

        # Invokes every receiver whose product held no change in `changes`,
        # with empty changes, so products that reconcile from the repository
        # see its current state. A fresh client cannot produce a delete change
        # for a config the backend withdrew while no client held it; this pass
        # is where such a withdrawal is detected.
        def reconcile(changes, repository)
          receivers.each do |receiver|
            receiver.call(repository, []) if matching_changes(changes, receiver).empty?
          end
          nil
        end

        private

        def matching_changes(changes, receiver)
          changes.select { |change| receiver.match?(change.path) }
        end

        # Store Matcher and block to be executed on a match
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

        # Matcher checks if the path matches
        class Matcher
          def initialize(&block)
            @block = block
          end

          def match?(path)
            @block.call(path)
          end

          # Matches on the product's path
          class Product < Matcher
            def initialize(products)
              block = ->(path) { products.include?(path.product) }
              super(&block)
            end
          end
        end
      end
    end
  end
end
