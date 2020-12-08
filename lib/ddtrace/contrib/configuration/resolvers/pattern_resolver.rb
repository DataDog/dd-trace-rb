require 'ddtrace/contrib/configuration/resolver'

module Datadog
  module Contrib
    module Configuration
      # Resolves a value to a configuration key
      module Resolvers
        # Matches strings against Regexps.
        class PatternResolver < Datadog::Contrib::Configuration::Resolver
          def resolve(name)
            return if patterns.empty?

            # Try to find a matching pattern
            matching_pattern = patterns.find do |pattern|
              if pattern.is_a?(Proc)
                (pattern === name)
              else
                (pattern === name.to_s) ||
                  (pattern == name) # Only required during configuration time.
              end
            end

            # Return match or default
            matching_pattern
          end

          def add(pattern)
            patterns << (pattern.is_a?(Regexp) || pattern.is_a?(Proc) ? pattern : pattern.to_s)
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
