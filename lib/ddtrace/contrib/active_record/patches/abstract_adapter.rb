require 'set'
require 'ddtrace/shim'

module Datadog
  module Contrib
    module ActiveRecord
      # Defines basic behaviors for an ActiveRecord event.
      module Patches
        module AbstractAdapter
          def self.included(base)
            if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.0.0')
              base.class_eval do
                alias_method :initialize_without_datadog, :initialize
                remove_method :initialize
                include InstanceMethods
              end
            else
              base.send(:prepend, InstanceMethods)
            end
          end

          # Compatibility shim for Rubies not supporting `.prepend`
          module InstanceMethodsCompatibility
            def initialize(&block)
              initialize_without_datadog(&block)
            end
          end

          # InstanceMethods - implementing instrumentation
          module InstanceMethods
            include InstanceMethodsCompatibility unless Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.0.0')

            EVENT_ACTIVERECORD_SQL = 'sql.active_record'.freeze

            def log(*args, &block)
              insert_shim! unless shim_inserted?
              super
            end

            private

            def shim_inserted?
              instance_variable_defined?(:@instrumenter) \
                && Datadog::Shim::Double.is_shim?(@instrumenter)
            end

            def insert_shim!
              @instrumenter = Datadog::Shim.double(@instrumenter) do |shim|
                connection = self

                shim.inject_method!(:instrument) do |*args, &block|
                  # Inject connection into arguments
                  if args[0] == EVENT_ACTIVERECORD_SQL && args[1].is_a?(Hash)
                    args[1][:connection] ||= connection
                  end

                  # Call original
                  shim.shim_target.instrument(*args, &block)
                end
              end
            end
          end
        end
      end
    end
  end
end
