# frozen_string_literal: true

require 'digest/sha1'
require_relative 'scope'
require_relative 'symbol_entry'

module Datadog
  module SymbolDatabase
    # Extracts symbol information from loaded Ruby classes/modules.
    #
    # @api private
    class Extractor
      def initialize(settings, logger)
        @settings = settings
        @logger = logger
        @includes = settings.symbol_database.includes
        @gem_paths = compute_gem_paths
        @stdlib_paths = compute_stdlib_paths
        @tracer_path = compute_tracer_path
      end

      # Extracts all user-code scopes from the current Ruby runtime.
      # Returns an array of MODULE scopes (one per source file).
      def extract
        scopes_by_file = Hash.new { |h, k| h[k] = [] }

        ObjectSpace.each_object(Module) do |mod|
          begin
            next unless extractable?(mod)

            source_file = find_source_file(mod)
            next unless source_file

            class_scope = extract_class(mod, source_file)
            scopes_by_file[source_file] << class_scope if class_scope
          rescue => e
            mod_name = begin
              mod.name
            rescue
              '(unknown)'
            end
            @logger.debug { "symbol_database: failed to extract #{mod_name}: #{e.class}: #{e}" }
          end
        end

        scopes_by_file.map do |file_path, class_scopes|
          build_module_scope(file_path, class_scopes)
        end
      end

      private

      def extractable?(mod)
        name = begin
          mod.name
        rescue
          nil
        end
        return false unless name
        return false if name.empty?
        return false if name.start_with?('Datadog')

        source_file = find_source_file(mod)
        return false unless source_file
        user_code_path?(source_file)
      end

      def find_source_file(mod)
        methods = begin
          mod.instance_methods(false) + mod.private_instance_methods(false) + mod.protected_instance_methods(false)
        rescue
          []
        end

        file_counts = Hash.new(0)
        methods.each do |method_name|
          begin
            location = mod.instance_method(method_name).source_location
            if location && location[0]
              file_counts[location[0]] += 1
            end
          rescue
            next
          end
        end

        # Prefer user code paths over gem/stdlib paths
        user_files = file_counts.select { |f, _| user_code_path?(f) }
        best = user_files.max_by { |_, count| count }
        best ? best[0] : nil
      end

      def user_code_path?(path)
        return false unless path
        return false unless path.start_with?('/')
        return false unless path.end_with?('.rb')
        return false if stdlib_path?(path)
        return false if gem_path?(path)
        return false if tracer_path?(path)
        return false if !@includes.empty? && !matches_includes?(path)
        true
      end

      def extract_class(mod, source_file)
        method_scopes = extract_methods(mod, source_file)
        return nil if method_scopes.empty?

        start_line = method_scopes.map(&:start_line).compact.min || 0
        end_line = method_scopes.map(&:end_line).compact.max || 0

        superclass_name = if mod.is_a?(Class) && mod.superclass && mod.superclass != Object
          mod.superclass.name
        end

        included = mod.included_modules
          .reject { |m| m == mod }
          .reject { |m| mod.is_a?(Class) && mod.superclass && mod.superclass.ancestors.include?(m) }
          .map { |m| m.name }
          .compact

        language_specifics = { access_modifiers: ['public'] }
        language_specifics[:super_classes] = [superclass_name] if superclass_name
        language_specifics[:interfaces] = included unless included.empty?

        Scope.new(
          scope_type: 'CLASS',
          name: mod.name,
          source_file: source_file,
          start_line: start_line,
          end_line: end_line,
          language_specifics: language_specifics,
          scopes: method_scopes,
        )
      end

      def extract_methods(mod, source_file)
        result = []

        { public: mod.public_instance_methods(false),
          protected: mod.protected_instance_methods(false),
          private: mod.private_instance_methods(false) }.each do |visibility, methods|
          methods.each do |method_name|
            begin
              um = mod.instance_method(method_name)
              location = um.source_location
              next unless location && location[0] == source_file

              params = extract_parameters(um)

              result << Scope.new(
                scope_type: 'METHOD',
                name: method_name.to_s,
                source_file: source_file,
                start_line: location[1],
                end_line: location[1],
                language_specifics: { access_modifiers: [visibility.to_s] },
                symbols: params.empty? ? nil : params,
              )
            rescue => e
              @logger.debug { "symbol_database: failed to extract method #{method_name}: #{e.class}: #{e}" }
            end
          end
        end

        result
      end

      def extract_parameters(method_obj)
        method_obj.parameters.filter_map do |type, name|
          next unless name
          SymbolEntry.new(
            symbol_type: 'ARG',
            name: name.to_s,
            line: 0,
          )
        end
      rescue => e
        @logger.debug { "symbol_database: failed to extract parameters: #{e.class}: #{e}" }
        []
      end

      def build_module_scope(file_path, class_scopes)
        file_hash = compute_file_hash(file_path)
        line_count = begin
          File.read(file_path).count("\n")
        rescue
          0
        end

        language_specifics = {}
        language_specifics[:file_hash] = file_hash if file_hash

        Scope.new(
          scope_type: 'MODULE',
          name: file_path,
          source_file: file_path,
          start_line: 1,
          end_line: line_count > 0 ? line_count : nil,
          language_specifics: language_specifics.empty? ? nil : language_specifics,
          scopes: class_scopes,
        )
      end

      def compute_file_hash(file_path)
        content = File.binread(file_path)
        header = "blob #{content.bytesize}\0"
        Digest::SHA1.hexdigest(header + content)
      rescue => e
        @logger.debug { "symbol_database: failed to hash #{file_path}: #{e.class}: #{e}" }
        nil
      end

      def gem_path?(path)
        @gem_paths.any? { |gp| path.start_with?(gp) }
      end

      def stdlib_path?(path)
        @stdlib_paths.any? { |sp| path.start_with?(sp) }
      end

      def tracer_path?(path)
        path.start_with?(@tracer_path)
      end

      def matches_includes?(path)
        @includes.any? { |prefix| path.include?(prefix) }
      end

      def compute_gem_paths
        paths = []
        paths << "#{Gem.dir}/gems/" if defined?(Gem)
        paths << "#{Gem.user_dir}/gems/" if defined?(Gem) && Gem.respond_to?(:user_dir)
        if defined?(Bundler) && Bundler.respond_to?(:bundle_path)
          paths << "#{Bundler.bundle_path}/"
        end
        paths << '/vendor/bundle/'
        paths.uniq
      rescue
        []
      end

      def compute_stdlib_paths
        paths = []
        paths << RbConfig::CONFIG['rubylibdir'] if RbConfig::CONFIG['rubylibdir']
        paths << RbConfig::CONFIG['archdir'] if RbConfig::CONFIG['archdir']
        paths.map { |p| p.end_with?('/') ? p : "#{p}/" }
      rescue
        []
      end

      def compute_tracer_path
        File.expand_path('../../..', __dir__)
      end
    end
  end
end
