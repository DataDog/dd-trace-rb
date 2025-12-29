# frozen_string_literal: true

require_relative 'path'
require_relative 'digest'

module Datadog
  module Core
    module Remote
      class Configuration
        # Content stores the information associated with a specific Configuration::Path
        class Content
          class << self
            def parse(hash)
              path = Path.parse(hash[:path])
              data = hash[:content]

              new(path: path, data: data)
            end
          end

          attr_reader :path, :data, :hashes, :apply_state, :apply_error
          attr_accessor :version

          def initialize(path:, data:)
            if data.nil?
              # +data+ is passed to Digest calculation and also is
              # unconditionally taken length of by +length+ method.
              # As such, the class is not written to expect +data+ to be nil.
              # Detect bad incoming values here to provide earlier diagnostics
              # when developing tests, for example.
              raise ArgumentError, 'data must not be nil'
            end
            unless String === data
              raise ArgumentError, "Invalid type for data: #{data.class}: expected String"
            end

            @path = path
            @data = data
            @apply_state = ApplyState::UNACKNOWLEDGED
            @apply_error = nil
            @hashes = {}
            @version = 0
          end

          def hexdigest(type)
            @hashes[type] || compute_and_store_hash(type)
          end

          def length
            @length ||= @data.size
          end

          # Sets this configuration as successfully applied.
          def applied
            @apply_state = ApplyState::ACKNOWLEDGED
            @apply_error = nil
          end

          # Sets this configuration as not successfully applied, with
          # a message describing the error.
          def errored(error_message)
            @apply_state = ApplyState::ERROR
            @apply_error = error_message
          end

          module ApplyState
            # Default state of configurations.
            # Set until the component consuming the configuration has acknowledged it was applied.
            UNACKNOWLEDGED = 1

            # Set when the configuration has been successfully applied.
            ACKNOWLEDGED = 2

            # Set when the configuration has been unsuccessfully applied.
            ERROR = 3
          end

          private

          def compute_and_store_hash(type)
            @hashes[type] = Digest.hexdigest(type, @data)
          end

          private_class_method :new
        end

        # ContentList stores a list of Content instances.
        # It provides convenient methods for finding content based on
        # Configuration::Path and Configuration::Target.
        class ContentList < Array
          class << self
            def parse(array)
              new.concat(array.map { |c| Content.parse(c) })
            end
          end

          def find_content(path, target)
            find { |c| c.path.eql?(path) && target.check(c) }
          end

          def [](path)
            find { |c| c.path.eql?(path) }
          end

          def []=(path, content)
            map! { |c| c.path.eql?(path) ? content : c }
          end

          def delete(path)
            idx = index { |e| e.path.eql?(path) }

            return if idx.nil?

            delete_at(idx)
          end

          def paths
            map(&:path).uniq
          end
        end
      end
    end
  end
end
