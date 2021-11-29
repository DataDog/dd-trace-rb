# typed: true
# frozen_string_literal: true

require 'set'
require 'json'

module Datadog
  module Profiling
    module Collectors
      class CodeProvenance
        def initialize(standard_library_path: RbConfig::CONFIG.fetch('rubylibdir'))
          @known_libraries = {}
          @library_paths = {}
          @seen_files = Set.new
          @seen_libraries = Set.new

          register_library(
            Library.new(
              type: 'standard library',
              name: 'ruby stdlib',
              version: RUBY_VERSION,
              path: standard_library_path,
            )
          )
        end

        def refresh(
          loaded_files: $LOADED_FEATURES,
          loaded_gems: Gem.loaded_specs.values
        )
          register_loaded_gems(loaded_gems)

          loaded_files.each do |file_path|
            next if seen_files.include?(file_path)
            seen_files << file_path

            _, found_library = library_paths.find { |library_path, _| file_path.start_with?(library_path) }
            seen_libraries << found_library if found_library
          end
        end

        def generate
          seen_libraries
        end

        def generate_json
          JSON.pretty_generate(v1: seen_libraries.to_a)
        end

        private

        attr_reader \
          :known_libraries,
          :library_paths,
          :seen_files,
          :seen_libraries

        def register_loaded_gems(loaded_gems)
          loaded_gems.each do |spec|
            next if known_libraries.key?(spec.name)

            register_library(Library.new(type: 'library', name: spec.name, version: spec.version, path: spec.gem_dir))
          end
        end

        def register_library(library)
          known_libraries[library.name] = library
          library_paths[library.path] = library
        end

        Library = Struct.new(:type, :name, :version, :path) do
          def initialize(type:, name:, version:, path:)
            super(type.freeze, name.dup.freeze, version.to_s.dup.freeze, path.dup.freeze)
            freeze
          end

          def to_json(*args)
            {type: type, name: name, version: version, path: path}.to_json(*args)
          end
        end
      end
    end
  end
end
