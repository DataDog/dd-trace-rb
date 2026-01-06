# frozen_string_literal: true

require_relative '../utils/fnv'
require_relative 'process'

module Datadog
  module Core
    module Environment
      # Creates a base hash that combines process and container tags
      # This is currently needed for DBM for back propagation.
      module BaseHash
        @mutex = Mutex.new
        @current_hash = nil
        @current_container_hash = nil

        class << self
          # Only compute a container hash if the agent returns a new Datadog-Container-Tags-Hash header
          #
          # @param container_tags_hash [String] hash received by the agent header
          # @return [Integer, nil] the new FNV hash value or nil
          def compute(container_tags_hash)
            return current if container_tags_hash.nil? || container_tags_hash.empty?

            @mutex.synchronize do
              if @current_container_hash == container_tags_hash
                return @current_hash
              end

              process_tags = Process.serialized
              data = process_tags + container_tags_hash

              new_hash = Core::Utils::FNV.fnv1_64(data)
              @current_hash = new_hash
              @current_container_hash = container_tags_hash
              new_hash
            end
          end

          # Get the current base hash value
          # @return [Integer, nil] the current FNV hash value or nil
          def current
            @mutex.synchronize { @current_hash }
          end

          # Reset the current hash value
          # @api private
          def reset!
            @mutex.synchronize do
              @current_hash = nil
              @current_container_hash = nil
            end
          end
        end
      end
    end
  end
end
