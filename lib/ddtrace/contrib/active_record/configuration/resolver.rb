require 'ddtrace/contrib/configuration/resolver'
require 'ddtrace/vendor/active_record/connection_specification'

module Datadog
  module Contrib
    module ActiveRecord
      module Configuration
        # Converts Symbols, Strings, and Hashes to a normalized connection settings Hash.
        class Resolver < Contrib::Configuration::Resolver
          def initialize(configurations = nil)
            @configurations = configurations
            @well_known_keys = {}
          end

          def resolve(key)
            return @well_known_keys[key] if @well_known_keys.key?(key)
            normalize(connection_resolver.resolve(key).symbolize_keys)
          end

          def add(key)
            @well_known_keys[key] = resolve(key)
          end

          def configurations
            @configurations || ::ActiveRecord::Base.configurations
          end

          def connection_resolver
            @resolver ||= begin
              if defined?(::ActiveRecord::ConnectionAdapters::ConnectionSpecification::Resolver)
                ::ActiveRecord::ConnectionAdapters::ConnectionSpecification::Resolver.new(configurations)
              else
                ::Datadog::Vendor::ActiveRecord::ConnectionAdapters::ConnectionSpecification::Resolver.new(
                  configurations
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
