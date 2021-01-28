require 'ddtrace/contrib/redis/vendor/resolver'

module Datadog
  module Contrib
    module Redis
      module Configuration
        UNIX_SCHEME = 'unix'.freeze

        # Converts Symbols, Strings, and Hashes to a normalized connection settings Hash.
        class Resolver < Contrib::Configuration::Resolver
          def resolve(key_or_hash)
            return :default if key_or_hash == :default

            normalize(connection_resolver.resolve(key_or_hash))
          end

          def normalize(hash)
            return { url: hash[:url] } if hash[:scheme] == UNIX_SCHEME

            # Connexion strings are always converted to host, port, db and scheme
            # but the host, port, db and scheme will generate the :url only after
            # establishing a first connexion
            {
              host: hash[:host],
              port: hash[:port],
              db: hash[:db],
              scheme: hash[:scheme]
            }
          end

          def connection_resolver
            @connection_resolver ||= ::Datadog::Contrib::Redis::Vendor::Resolver.new
          end
        end
      end
    end
  end
end
