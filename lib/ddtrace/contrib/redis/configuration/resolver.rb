module Datadog
  module Contrib
    module Redis
      module Configuration
        # Converts Symbols, Strings, and Hashes to a normalized connection settings Hash.
        class Resolver
          attr_reader :options
          # Redis::Client@options
          def initialize(options)
            @options = options
          end

          def resolve
            possible_configurations.each do |conf|
              if Datadog.configuration[:redis, conf] != Datadog.configuration[:redis]
                return Datadog.configuration[:redis, conf]
              end
            end
            Datadog.configuration[:redis]
          end

          def possible_configurations
            resolved_config = []
            if options[:url]
              resolved_config << options[:url]

              require 'uri'
              uri = URI(options[:url])

              return resolved_config if uri.scheme == 'unix'
            end

            resolved_config.concat(
              [
                { host: options[:host], port: options[:port], db: options[:db] },
                { host: options[:host], port: options[:port] },
                { host: options[:host], db: options[:db] },
                { host: options[:host] }
              ]
            )
          end
        end
      end
    end
  end
end
