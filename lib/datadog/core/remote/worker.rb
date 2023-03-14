# frozen_string_literal: true

module Datadog
  module Core
    module Remote
      class Worker
        def initialize(interval:, &block)
          @mutex = Mutex.new
          @thr = nil

          @starting = false
          @stopping = false
          @started = false

          @interval = interval
          @block = block
        end

        def start
          Datadog.logger.debug { 'remote worker starting' }

          @mutex.lock

          return if @starting || @started

          @starting = true

          @thr = Thread.new { poll(@interval) }

          @started = true
          @starting = false

          Datadog.logger.debug { 'remote worker started' }
        ensure
          @mutex.unlock
        end

        def stop
          Datadog.logger.debug { 'remote worker stopping' }

          @mutex.lock

          @stopping = true

          @thr.kill unless @thr.nil?

          @started = false
          @stopping = false

          Datadog.logger.debug { 'remote worker stopped' }
        ensure
          @mutex.unlock
        end

        def started?
          @started
        end

        private

        def poll(interval)
          loop do
            break unless @mutex.synchronize { @starting || @started }

            call

            sleep(interval)
          end
        end

        def call
          Datadog.logger.debug { 'remote worker perform' }

          @block.call
        end
      end
    end
  end
end
