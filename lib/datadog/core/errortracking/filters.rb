module Datadog
  module Core
    module Errortracking
      # Filters module provide the different‡
      module Filters
        class << self
          def _get_gem_name(file_path)
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
            instrumented_files.key?(file_path)
          end

          def generate_filter(to_instrument, instrumented_files = nil)
            case to_instrument
            when 'all'
              return proc { |file_path| !_is_datadog(file_path) }
            when 'user'
              if instrumented_files
                return proc { |file_path|
                  _is_user_code(file_path) || _is_instrumented_modules(file_path, instrumented_files)
                }
              else
                return proc { |file_path| _is_user_code(file_path) }
              end
            when 'third_party'
              if instrumented_files
                return proc { |file_path|
                  _is_third_party(file_path) || _is_instrumented_modules(file_path, instrumented_files)
                }
              else
                return proc { |file_path| _is_third_party(file_path) }
              end
            end

            proc { |file_path| _is_instrumented_modules(file_path, instrumented_files) }
          end
        end
      end
    end
  end
end
