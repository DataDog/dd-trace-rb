require 'ddtrace/contrib/configuration/resolver'
require 'ddtrace/vendor/active_record/connection_specification'

module Datadog
  module Contrib
    module ActiveRecord
      module Configuration
        # Converts Symbols, Strings, and Hashes to a normalized connection settings Hash.
        class Resolver < Contrib::Configuration::Resolver
          def initialize(active_record_configurations = nil, &block)
            super(&block)
            @active_record_configurations = active_record_configurations
          end

          def resolve(key)
            super(expand_key(key))
          end

          def add(key, config = nil)
            super(expand_key(key), config)
          end

          def expand_key(key)
            return :default if key == :default
            normalize(connection_resolver.resolve(key).symbolize_keys)
          end

          def active_record_configurations
            @active_record_configurations || ::ActiveRecord::Base.configurations
          end

          def connection_resolver
            @resolver ||= begin
              if defined?(::ActiveRecord::ConnectionAdapters::ConnectionSpecification::Resolver)
                ::ActiveRecord::ConnectionAdapters::ConnectionSpecification::Resolver.new(active_record_configurations)
              else
                ::Datadog::Vendor::ActiveRecord::ConnectionAdapters::ConnectionSpecification::Resolver.new(
                  active_record_configurations
                )
              end
            end
          end

          def normalize(hash)
            {
              adapter:  hash[:adapter],
              host:     hash[:host],
              port:     hash[:port],
              database: hash[:database],
              username: hash[:username]
            }
          end
        end
      end
    end
  end
end
