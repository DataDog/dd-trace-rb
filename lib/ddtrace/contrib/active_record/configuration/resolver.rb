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
          end

          def resolve(key)
            normalize(connection_resolver.resolve(key).symbolize_keys)
          end

          def configurations
            @configurations || ::ActiveRecord::Base.configurations
          end

          def connection_resolver
            @resolver ||= begin
              if defined?(::ActiveRecord::ConnectionAdapters::ConnectionSpecification::Resolver)
                ::ActiveRecord::ConnectionAdapters::ConnectionSpecification::Resolver.new(configurations)
              else
                ::Datadog::Vendor::ActiveRecord::ConnectionAdapters::ConnectionSpecification::Resolver.new(configurations)
              end
            end
          end

          def normalize(hash)
            # TODO: move to Sqlite3Resolver
            adapter = hash[:adapter]
            database = hash[:database]
            if adapter == 'sqlite3'
              database = database.sub(::Rails.root.to_s + '/', '')
            end

            {
              adapter:  adapter,
              host:     hash[:host],
              port:     hash[:port],
              database: database,
              username: hash[:username]
            }
          end
          #
          # class Key < Hash
          #   def hash
          #     slice(:adapter, :host, :port, :username).hash
          #   end
          #
          #   def eql?(other)
          #     slice(:adapter, :host, :port, :username) == other.slice(:adapter, :host, :port, :username) &&
          #       (self[:database] == other[:database] || (self[:database] && self[:database].end_with?(other[:database])))
          #   end
          # end
        end
      end
    end
  end
end
