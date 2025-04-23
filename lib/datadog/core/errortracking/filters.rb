module Datadog
  module Core
    module Errortracking
      module Filters
        class << self
          def _get_gem_name(file_path)
            regex = /gems\/([^\/]+)-\d/
            regex_match = regex.match(file_path)
            return unless regex_match
            gem_name = regex_match[1]

            begin
              return Gem::Specification::find_by_name(gem_name)
            rescue => each
              return nil
            end
          end

          def _is_user_code(file_path)
            !_get_gem_name(file_path)
          end

          def _is_datadog(file_path)
            file_path.include?('lib/datadog/')
          end

          def _is_third_party(file_path)
            _get_gem_name(file_path) && !_is_datadog(file_path)
          end

          def _is_instrumented_modules(file_path, instrumented_files)
            instrumented_files.has_key?(file_path)
          end

          def generate_filter(to_instrument, instrumented_files = nil)
            case to_instrument
            when "all"
              proc { |file_path| !_is_datadog(file_path) }
            when "user"
              if instrumented_files
                proc { |file_path| _is_user_code(file_path) || _is_instrumented_modules(file_path, instrumented_files) }
              else
                proc { |file_path| _is_user_code(file_path) }
              end
            when "third_party"
              if instrumented_files
                proc { |file_path| _is_third_party(file_path) || _is_instrumented_modules(file_path, instrumented_files) }
              else
                proc { |file_path| _is_third_party(file_path) }
              end
            when nil
              if instrumented_files
                proc { |file_path| _is_instrumented_modules(file_path, instrumented_files) }
              end
            end
            #   else
            #     # Replace by log
            #     # raise ArgumentError, "ErrorTracker: must provide either 'to_instrument' or 'instrumented_files'"
            #   end
            # else
            #   # Replace by log
            #   # raise ArgumentError, "ErrorTracker: invalid value '#{to_instrument}' for 'to_instrument' option. Expected 'all', 'user', or 'third_party'."
            # end
          end
        end
      end
    end
  end
end
