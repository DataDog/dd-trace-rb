require 'set'
require 'ddtrace/augmentation/shim'

module Datadog
  module Contrib
    module ActiveRecord
      # Defines basic behaviors for an ActiveRecord event.
      module Patches
        # Adds patch to AbstractAdapter to make it pass more information through
        # ActiveSupport notifications, for better instrumentation.
        module AbstractAdapter
          def self.included(base)
            if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.0.0')
              base.class_eval do
                alias_method :log_without_datadog, :log
                remove_method :log
                include InstanceMethods
              end
            else
              base.send(:prepend, InstanceMethods)
            end
          end

          # Compatibility shim for Rubies not supporting `.prepend`
          module InstanceMethodsCompatibility
            def log(*args, &block)
              log_without_datadog(*args, &block)
            end
          end

          # InstanceMethods - implementing instrumentation
          module InstanceMethods
            include InstanceMethodsCompatibility unless Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.0.0')

            EVENT_ACTIVERECORD_SQL = 'sql.active_record'.freeze

            # Override #log since sometimes connections are initialized prior
            # to when the patch is applied; this will allow existing connections
            # to receive the Shim as well.
            def log(*args, &block)
              insert_shim! unless shim_inserted?
              super
            end

            private

            def shim_inserted?
              instance_variable_defined?(:@instrumenter) \
                && Datadog::Shim.shim?(@instrumenter)
            end

            def insert_shim!
              @instrumenter = Datadog::Shim.new(@instrumenter) do |shim|
                connection = self

                shim.override_method!(:instrument) do |*args, &block|
                  # Inject connection into arguments
                  if args[0] == EVENT_ACTIVERECORD_SQL && args[1].is_a?(Hash)
                    args[1][:connection] ||= connection
                  end

                  # Call original
                  shim_target.instrument(*args, &block)
                end
              end
            end
          end
        end
      end
    end
  end
end
