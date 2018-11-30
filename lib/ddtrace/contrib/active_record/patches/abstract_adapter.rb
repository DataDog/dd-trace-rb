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

            def initialize(*args)
              super

              @instrumenter = Datadog::Shim::Double.new(@instrumenter) do
                puts "PATCHING #{shim.object_id}..."
                wrap_method_once(:instrument) do |original, *args, &block|
                  # puts "\nIntercepting...\n"
                  # pp args if args[0] == EVENT_ACTIVERECORD_SQL
                  # Inject connection config into arguments
                  if args[0] == EVENT_ACTIVERECORD_SQL && args[1].is_a?(Hash)
                    args[1][:connection_config] ||= @config
                    puts "MODIFIED!"
                    # pp caller
                  end

                  # Call original
                  original.call(*args, &block)
                end
              end
              # binding.pry
              # # # Wrap #instrument calls to this object
              # Datadog::Shim.wrap_method_once(@instrumenter, :instrument) do |original, *args, &block|
              #   puts "\nIntercepting...\n"
              #   pp args if args[0] == EVENT_ACTIVERECORD_SQL
              #   # Inject connection config into arguments
              #   if args[0] == EVENT_ACTIVERECORD_SQL && args[1].is_a?(Hash)
              #     args[1][:connection_config] ||= @config
              #   end

              #   # Call original
              #   original.call(*args, &block)
              # end
            end
          end
        end
      end
    end
  end
end
