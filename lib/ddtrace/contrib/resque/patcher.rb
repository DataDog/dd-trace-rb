module Datadog
  module Contrib
    # Namespace for `resque` integration
    module Resque
      SERVICE = 'resque'.freeze

      class << self
        # Globally-acccesible reference for pre-forking optimization
        attr_accessor :sync_writer
      end

      # Patcher for Resque integration - sets up the pin for the integration
      module Patcher
        include Base
        register_as :resque, auto_patch: true
        option :service_name, default: SERVICE

        @patched = false
        option :workers, default: []

        class << self
          def patch
            return @patched if patched? || !defined?(::Resque)

            require 'ddtrace/ext/app_types'
            require_relative 'resque_job'

            add_pin
            get_option(:workers).each { |worker| worker.extend(ResqueJob) }
            @patched = true
          rescue => e
            Tracer.log.error("Unable to apply Resque integration: #{e}")
            @patched
          end

          def patched?
            @patched
          end

          private

          def add_pin
            Pin
              .new(get_option(:service_name), app: 'resque', app_type: Ext::AppTypes::WORKER)
              .onto(::Resque)
          end
        end
      end
    end
  end
end
