# frozen_string_literal: true

module Datadog
  module Core
    module Utils
      # Methods from future versions of Ruby implemented in for older rubies.
      #
      # This helps keep the project using newer APIs for never rubies and
      # facilitates cleaning up when support for an older versions of Ruby is removed.
      module Backport
        # `String` class backports.
        module String
          module_function

          if ::String.method_defined?(:delete_prefix)
            def delete_prefix(string, prefix)
              string.delete_prefix(prefix)
            end
          else
            def delete_prefix(string, prefix)
              prefix = prefix.to_s
              if string.start_with?(prefix)
                string[prefix.length..-1]
              else
                string.dup
              end
            end
          end
        end
      end
    end
  end
end
