module Datadog
  module Contrib
    module Redis
      module Configuration
        # Converts Symbols, Strings, and Hashes to a normalized connection settings Hash.
        class Resolver < Contrib::Configuration::Resolver

          def resolve(key_or_hash)
            return :default if key_or_hash == :default

            normalize(key_or_hash).tap { |x| puts x.inspect }
          end

          def normalize(hash)
            resolved_configuration = resolve_configuration(hash)
            {
              url: resolved_configuration[:url],
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
