require 'ddtrace/contrib/configuration/resolver'

module Datadog
  module Contrib
    module Configuration
      # Resolves a value to a configuration key
      module Resolvers
        # Matches strings against Regexps.
        class RegexpResolver < Datadog::Contrib::Configuration::Resolver
          def add_key(pattern)
            patterns << pattern.is_a?(Regexp) ? pattern : /#{Regexp.quote(pattern)}/
          end

          def resolve(name)
            return :default if name == :default

            name = name.to_s
            matching_pattern = patterns.find { |p| p =~ name }
            matching_pattern || :default
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
