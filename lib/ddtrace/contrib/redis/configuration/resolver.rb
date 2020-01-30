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

            resolved_hosts_config = resolved_hosts(options[:host]).map do |resolved_host|
              [
                { host: resolved_host, port: options[:port], db: options[:db] },
                { host: resolved_host, port: options[:port] },
                { host: resolved_host, db: options[:db] },
                { host: resolved_host }
              ]
            end.flatten
            resolved_config.concat(resolved_hosts_config)
          end

          # make sure that the configuration will be matched against hostnames as well
          def resolved_hosts(host)
            require 'resolv'

            resolved = [host]
            resolved += Resolv.getaddresses(host)
            resolved += Resolv.getnames(host)
          rescue Resolv::ResolvError
            # Resolv.getnames('localhost') raises
            # Resolv::ResolvError (cannot interpret as address: localhost)
            resolved
          end
        end
      end
    end
  end
end
