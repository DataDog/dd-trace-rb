require 'ddtrace/contrib/active_record/configuration/connection_specification'

module Datadog
  module Contrib
    module ActiveRecord
      module Configuration
        # Converts Symbols, Strings, and Hashes to a normalized connection settings Hash.
        class Resolver
          def initialize(configurations)
            if defined?(::ActiveRecord::ConnectionAdapters::ConnectionSpecification::Resolver)
              @resolver = ::ActiveRecord::ConnectionAdapters::ConnectionSpecification::Resolver.new(configurations)
            else
              @resolver = ConnectionSpecification::Resolver.new(configurations)
            end
          end

          def resolve(spec)
            normalize(@resolver.resolve(spec).symbolize_keys)
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
