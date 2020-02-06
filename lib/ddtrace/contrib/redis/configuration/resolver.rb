module Datadog
  module Contrib
    module Redis
      module Configuration
        # Converts Symbols, Strings, and Hashes to a normalized connection settings Hash.
        class Resolver < Contrib::Configuration::Resolver
          def resolve(key_or_hash)
            return :default if key_or_hash == :default

            normalize(key_or_hash)
          end

          def normalize(hash)
            resolved_configuration = resolve_configuration(hash)
            return { url: resolved_configuration[:url] } if resolved_configuration[:scheme] == 'unix'

            # Connexion strings are always converted to host, port, db and scheme
            # but the host, port, db and scheme will generate the :url only after
            # establishing a first connexion
            {
              host: resolved_configuration[:host],
              port: resolved_configuration[:port],
              db: resolved_configuration[:db],
              scheme: resolved_configuration[:scheme]
            }
          end

          # The option parsing in Redis::Client is implemented as a instance method
          # of the client itself. Since it cannot be imported from a library module
          # the configuration will be resolved within a new redis instance
          def resolve_configuration(options)
            ::Redis::Client.new(options).options
          end
        end
      end
    end
  end
end
