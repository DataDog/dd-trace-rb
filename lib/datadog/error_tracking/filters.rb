# frozen_string_literal: true

module Datadog
  module ErrorTracking
    # The filters module is in charge of creating
    # the filter function called in the handled_exc_tracker.
    #
    # @api private
    module Filters
      module_function

      def get_gem_name(file_path)
        regex = %r{gems/([^/]+)-\d}
        regex_match = regex.match(file_path)
        return unless regex_match

        gem_name = regex_match[1]

        begin
          Gem::Specification.find_by_name(gem_name)
        rescue
          nil
        end
      end

      def user_code?(file_path)
        !get_gem_name(file_path)
      end

      def datadog_code?(file_path)
        file_path.include?('lib/datadog/')
      end

      def third_party_code?(file_path)
        get_gem_name(file_path) && !datadog_code?(file_path)
      end

      def instrumented_module?(file_path, instrumented_files)
        instrumented_files.include?(file_path)
      end

      # Generate the proc used in the tracepoint
      def generate_filter(to_instrument_scope, handled_errors_include = nil)
        case to_instrument_scope
        when 'all'
          return proc { |file_path| !datadog_code?(file_path) }
        when 'user'
          if handled_errors_include
            return proc { |file_path|
              user_code?(file_path) || instrumented_module?(file_path, handled_errors_include)
            }
          else
            return proc { |file_path| user_code?(file_path) }
          end
        when 'third_party'
          if handled_errors_include
            return proc { |file_path|
              third_party_code?(file_path) || instrumented_module?(file_path, handled_errors_include)
            }
          else
            return proc { |file_path| third_party_code?(file_path) }
          end
        end

        # If only handled_errors_include is set
        proc { |file_path| instrumented_module?(file_path, handled_errors_include) }
      end
    end
  end
end
