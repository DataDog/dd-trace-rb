require 'ddtrace/contrib/configuration/resolver'

module Datadog
  module Contrib
    module Configuration
      # Resolves a value to a configuration key
      module Resolvers
        # Matches strings against Regexps.
        class PatternResolver < Datadog::Contrib::Configuration::Resolver
          def resolve(name)
            # Try to find a matching pattern
            matching_pattern = patterns.find do |pattern|
              if pattern.is_a?(Proc)
                pattern === name
              elsif pattern.is_a?(Regexp)
                if name.is_a?(Regexp)
                  name.to_s === pattern.to_s
                elsif name.respond_to?(:to_s)
                  pattern.match(name.to_s)
                else
                  false
                end
              else
                pattern === name.to_s # Co-erce to string
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
