# typed: false
# frozen_string_literal: true

require 'set'
require 'json'

module Datadog
  module Profiling
    module Collectors
      # Collects library metadata for loaded files ($LOADED_FEATURES) in the Ruby VM.
      # The output of this class is a list of libraries which have been require'd (in particular, this is
      # not a list of ALL installed libraries).
      #
      # This metadata powers grouping and categorization of stack trace data.
      #
      class CodeProvenance
        def initialize(standard_library_path: RbConfig::CONFIG.fetch('rubylibdir'))
          @libraries_by_name = {}
          @libraries_by_path = {}
          @seen_files = Set.new
          @seen_libraries = Set.new

          record_library(
            Library.new(
              type: 'standard library',
              name: 'stdlib',
              version: RUBY_VERSION,
              path: standard_library_path,
            )
          )
        end

        def refresh(loaded_files: $LOADED_FEATURES, loaded_specs: Gem.loaded_specs.values)
          record_loaded_specs(loaded_specs)
          record_loaded_files(loaded_files)

          self
        end

        def generate
          seen_libraries
        end

        def generate_json
          JSON.fast_generate(v1: seen_libraries.to_a)
        end

        private

        attr_reader \
          :libraries_by_name,
          :libraries_by_path,
          :seen_files,
          :seen_libraries

        def record_library(library)
          libraries_by_name[library.name] = library
          libraries_by_path[library.path] = library
        end

        def record_loaded_specs(loaded_specs)
          loaded_specs.each do |spec|
            next if libraries_by_name.key?(spec.name)

            record_library(Library.new(type: 'library', name: spec.name, version: spec.version, path: spec.gem_dir))
          end
        end

        def record_loaded_files(loaded_files)
          loaded_files.each do |file_path|
            next if seen_files.include?(file_path)

            seen_files << file_path

            _, found_library = libraries_by_path.find { |library_path, _| file_path.start_with?(library_path) }
            seen_libraries << found_library if found_library
          end
        end

        Library = Struct.new(:type, :name, :version, :path) do
          def initialize(type:, name:, version:, path:)
            super(type.freeze, name.dup.freeze, version.to_s.dup.freeze, path.dup.freeze)
            freeze
          end

          def to_json(*args)
            { type: type, name: name, version: version, paths: [path] }.to_json(*args)
          end
        end
      end
    end
  end
end
