require 'ddtrace/contrib/redis/vendor/resolver'

module Datadog
  module Contrib
    module Redis
      module Configuration
        UNIX_SCHEME = 'unix'.freeze

        # Converts String URLs and Hashes to a normalized connection settings Hash.
        class Resolver < Contrib::Configuration::Resolver
          # @param [Hash,String] Redis connection information
          def resolve(hash)
            super(parse_matcher(hash))
          end

          protected

          def parse_matcher(matcher)
            matcher = { url: matcher } if matcher.is_a?(String)

            normalize(connection_resolver.resolve(matcher))
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
