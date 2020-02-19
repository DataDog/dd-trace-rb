require 'ddtrace/contrib/configuration/resolver'

module Datadog
  module Contrib
    module Configuration
      # Resolves a value to a configuration key
      module Resolvers
        # Matches strings against Regexps.
        class RegexpResolver < Datadog::Contrib::Configuration::Resolver
          def resolve(name)
            # Co-erce to string
            name = name.to_s

            # Try to find a matching pattern
            matching_pattern = patterns.find do |pattern|
              pattern.is_a?(Regexp) ? pattern =~ name : pattern == name
            end

            # Return match or default
            matching_pattern || :default
          end

          def add(pattern)
            patterns << (pattern.is_a?(Regexp) ? pattern : pattern.to_s)
          end

          private

          def patterns
            @patterns ||= Set.new
          end
        end
      end
    end
  end
end
