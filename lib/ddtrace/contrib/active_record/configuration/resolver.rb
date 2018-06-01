require 'ddtrace/contrib/configuration/resolver'
require 'ddtrace/contrib/active_record/configuration/connection_specification'

module Datadog
  module Contrib
    module ActiveRecord
      module Configuration
        # Converts Symbols, Strings, and Hashes to a normalized connection settings Hash.
        class Resolver < Contrib::Configuration::Resolver
          def initialize(configurations = nil)
            @configurations = configurations
          end

          def configurations
            @configurations || ::ActiveRecord::Base.configurations
          end

          def connection_resolver
            @resolver ||= begin
              if defined?(::ActiveRecord::ConnectionAdapters::ConnectionSpecification::Resolver)
                ::ActiveRecord::ConnectionAdapters::ConnectionSpecification::Resolver.new(configurations)
              else
                ConnectionSpecification::Resolver.new(configurations)
              end
            end
          end

          def resolve(spec)
            return :default if spec == :default
            normalize(connection_resolver.resolve(spec).symbolize_keys)
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
