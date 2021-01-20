require 'ddtrace/contrib/configuration/resolver'
require 'ddtrace/vendor/active_record/connection_specification'

module Datadog
  module Contrib
    module ActiveRecord
      module Configuration
        # Converts Symbols, Strings, and Hashes to a normalized connection settings Hash.
        #
        # When matching using a Hash, these are the valid fields:
        # ```
        # {
        #   adapter: ...,
        #   host: ...,
        #   port: ...,
        #   database: ...,
        #   username: ...,
        #   role: ...,
        # }
        # ```
        #
        # Partial matching is supported: not including certain fields or setting them to `nil`
        # will cause them to matching all values for that field. For example: `database: nil`
        # will match any database, given the remaining fields match.
        #
        # Any fields not listed above are discarded.
        #
        # When more than one configuration could be matched, the last one to match is selected,
        # based on addition order (`#add`).
        class Resolver < Contrib::Configuration::Resolver
          def initialize(active_record_configuration = nil)
            super()

            @active_record_configuration = active_record_configuration
          end

          def active_record_configuration
            @active_record_configuration || ::ActiveRecord::Base.configurations
          end

          def add(matcher, value)
            parsed = parse_matcher(matcher)

            # In case of error parsing, don't store `nil` key
            # as it wouldn't be useful for matching configuration
            # hashes in `#resolve`.
            super(parsed, value) if parsed
          end

          def resolve(db_config)
            active_record_config = connection_resolver.resolve(db_config).symbolize_keys

            hash = normalize(active_record_config)

            # Hashes in Ruby maintain insertion order
            _, config = @configurations.reverse_each.find do |matcher, _|
              matcher.none? do |key, value|
                value != hash[key]
              end
            end

            config
          rescue => e
            Datadog.logger.error(
              "Failed to resolve ActiveRecord configuration key #{db_config.inspect}. " \
              "Cause: #{e.message} Source: #{e.backtrace.first}"
            )

            nil
          end

          protected

          def parse_matcher(matcher)
            resolved_pattern = connection_resolver.resolve(matcher).symbolize_keys
            normalized = normalize(resolved_pattern)

            # Remove empty fields to allow for partial matching
            normalized.reject! { |_, v| v.nil? }

            normalized
          rescue => e
            Datadog.logger.error(
              "Failed to resolve ActiveRecord configuration key #{matcher.inspect}. " \
              "Cause: #{e.message} Source: #{e.backtrace.first}"
            )
          end

          def connection_resolver
            @resolver ||= begin
              if defined?(::ActiveRecord::ConnectionAdapters::ConnectionSpecification::Resolver)
                ::ActiveRecord::ConnectionAdapters::ConnectionSpecification::Resolver.new(active_record_configuration)
              else
                ::Datadog::Vendor::ActiveRecord::ConnectionAdapters::ConnectionSpecification::Resolver.new(
                  active_record_configuration
                )
              end
            end
          end

          # Extract only fields we'd like to match
          # from the ActiveRecord configuration.
          def normalize(active_record_config)
            {
              adapter:  active_record_config[:adapter],
              host:     active_record_config[:host],
              port:     active_record_config[:port],
              database: active_record_config[:database],
              username: active_record_config[:username]
            }
          end
        end
      end
    end
  end
end
