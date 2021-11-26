# typed: true
# frozen_string_literal: true

require 'set'

# Todo: rename to provenance
# Todo: separate unknown cases (not in valid loaded file) from user code

module Datadog
  module Profiling
    module Pprof
      # This class is used to assign a given file as:
      #
      # * belonging to a given gem
      # * the standard library
      # * none of them (usually eval'd code or application code)
      #
      # This information is then represented in pprofs (ab)using mappings.
      class CodeIdentification
        RUBY_STANDARD_LIBRARY_MARKER = 'ruby-standard-library'
        USER_CODE_OR_UKNOWN_MAPPING = 0

        private

        attr_reader \
          :loaded_files,
          :library_paths,
          :mapping_id_for,
          :path_mapping_id_cache

        public

        def initialize(
          mapping_id_for:,
          loaded_files: Set.new($LOADED_FEATURES),
          loaded_gems: Gem.loaded_specs.values,
          standard_library_path: RbConfig::CONFIG.fetch('rubylibdir')
        )
          @loaded_files = loaded_files
          @library_paths = initialize_library_paths(loaded_gems, standard_library_path)
          @mapping_id_for = mapping_id_for
          @path_mapping_id_cache = {}
        end

        def mapping_for(path)
          path_mapping_id_cache[path] ||= fetch_mapping_for(path)
        end

        private

        def fetch_mapping_for(path)
          return USER_CODE_OR_UKNOWN_MAPPING unless valid_loaded_file?(path)

          found_library_path, found_library_build = library_paths.find { |library_path, _| path.start_with?(library_path) }

          return USER_CODE_OR_UKNOWN_MAPPING unless found_library_build

          mapping_id_for.call(filename: found_library_path, build_id: found_library_build)
        end

        def initialize_library_paths(loaded_gems, standard_library_path)
          library_paths = loaded_gems.each_with_object({}) { |spec, output| output[spec.gem_dir] = spec.full_name }
          library_paths[standard_library_path] = RUBY_STANDARD_LIBRARY_MARKER

          library_paths
        end

        def valid_loaded_file?(path)
          loaded_files.include?(path)
        end
      end
    end
  end
end
