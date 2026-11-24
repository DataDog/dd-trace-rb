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
          nil
        end

        # Calls each receiver that declares initial-reconcile participation and has no
        # matching change in `changes`, passing an empty change list.
        def reconcile(changes, repository)
          receivers.each do |receiver|
            next unless receiver.initial_reconcile?

            receiver.call(repository, []) unless any_matching?(changes, receiver)
          end
          nil
        end

        private

        def matching_changes(changes, receiver)
          changes.select { |change| receiver.match?(change.path) }
        end

        def any_matching?(changes, receiver)
          changes.any? { |change| receiver.match?(change.path) }
        end

        # Store Matcher and block to be executed on a match
        class Receiver
          def initialize(matcher, initial_reconcile: false, &block)
            @block = block
            @initial_reconcile = initial_reconcile
            @matcher = matcher
          end

          def match?(path)
            @matcher.match?(path)
          end

          # Whether #reconcile may call this receiver with an empty change
          # list on the client's first sync. A participating receiver must
          # act on the repository's current contents when the change list is
          # empty.
          def initial_reconcile?
            @initial_reconcile
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
