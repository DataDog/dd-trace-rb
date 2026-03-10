# frozen_string_literal: true

require_relative 'scope'
require_relative 'symbol'
require_relative 'file_hash'

module Datadog
  module SymbolDatabase
    # Extracts symbol metadata from loaded Ruby modules and classes via introspection.
    #
    # Uses Ruby's reflection APIs (Module#constants, Class#instance_methods, Method#parameters)
    # to build hierarchical Scope structures representing code organization.
    # Filters to user code only (excludes gems, stdlib, test files).
    #
    # Extraction flow:
    # 1. ObjectSpace.each_object(Module) - Iterate all loaded modules/classes
    # 2. Filter to user code (user_code_module?)
    # 3. Build MODULE or CLASS scope with nested METHOD scopes
    # 4. Extract symbols: constants, class variables, method parameters
    #
    # Called by: Component.extract_and_upload (during upload trigger)
    # Produces: Scope objects passed to ScopeContext for batching
    # File hashing: Calls FileHash.compute for MODULE scopes
    #
    # @api private
    class Extractor
      # Extract symbols from a module or class.
      # Returns nil if module should be skipped (anonymous, gem code, stdlib).
      # @param mod [Module, Class] The module or class to extract from
      # @return [Scope, nil] Extracted scope with nested scopes/symbols, or nil if filtered out
      def self.extract(mod)
        return nil unless mod.is_a?(Module)
        return nil unless mod.name  # Skip anonymous modules/classes
        return nil unless user_code_module?(mod)

        if mod.is_a?(Class)
          extract_class_scope(mod)
        else
          extract_module_scope(mod)
        end
      rescue => e
        Datadog.logger.debug("SymDB: Failed to extract #{mod.name}: #{e.class}: #{e}")
        nil
      end

      # Check if module is from user code (not gems or stdlib)
      # @param mod [Module] The module to check
      # @return [Boolean] true if user code
      def self.user_code_module?(mod)
        source_file = find_source_file(mod)
        return false unless source_file

        user_code_path?(source_file)
      end

      # Check if path is user code
      # @param path [String] File path
      # @return [Boolean] true if user code
      def self.user_code_path?(path)
        # Exclude gem paths
        return false if path.include?('/gems/')
        # Exclude Ruby stdlib
        return false if path.include?('/ruby/')
        return false if path.start_with?('<internal:')
        return false if path.include?('(eval)')
        # Exclude spec files (test code, not application code)
        return false if path.include?('/spec/')

        true
      end

      # Find source file for a module
      # @param mod [Module] The module
      # @return [String, nil] Source file path or nil
      def self.find_source_file(mod)
        # Try instance methods first
        mod.instance_methods(false).each do |method_name|
          method = mod.instance_method(method_name)
          location = method.source_location
          return location[0] if location
        end

        # Try singleton methods
        mod.singleton_methods(false).each do |method_name|
          method = mod.method(method_name)
          location = method.source_location
          return location[0] if location
        end

        nil
      rescue
        nil
      end

      # Extract MODULE scope
      # @param mod [Module] The module
      # @return [Scope] The module scope
      def self.extract_module_scope(mod)
        source_file = find_source_file(mod)

        Scope.new(
          scope_type: 'MODULE',
          name: mod.name,
          source_file: source_file,
          start_line: 0,
          end_line: 2147483647,  # INT_MAX (entire file)
          language_specifics: build_module_language_specifics(mod, source_file),
          scopes: extract_nested_classes(mod),
          symbols: extract_module_symbols(mod)
        )
      end

      # Extract CLASS scope
      # @param klass [Class] The class
      # @return [Scope] The class scope
      def self.extract_class_scope(klass)
        methods = klass.instance_methods(false)
        start_line, end_line = calculate_class_line_range(klass, methods)
        source_file = find_source_file(klass)

        Scope.new(
          scope_type: 'CLASS',
          name: klass.name,
          source_file: source_file,
          start_line: start_line,
          end_line: end_line,
          language_specifics: build_class_language_specifics(klass),
          scopes: extract_method_scopes(klass),
          symbols: extract_class_symbols(klass)
        )
      end

      # Calculate class line range from method locations
      # @param klass [Class] The class
      # @param methods [Array<Symbol>] Method names
      # @return [Array<Integer, Integer>] [start_line, end_line]
      def self.calculate_class_line_range(klass, methods)
        lines = methods.filter_map do |method_name|
          method = klass.instance_method(method_name)
          location = method.source_location
          location[1] if location && location[0]
        end

        return [0, 2147483647] if lines.empty?

        [lines.min, lines.max]
      rescue
        [0, 2147483647]
      end

      # Build language specifics for MODULE
      # @param mod [Module] The module
      # @param source_file [String, nil] Source file path
      # @return [Hash] Language-specific metadata
      def self.build_module_language_specifics(mod, source_file)
        specifics = {}

        # Compute file hash if source file available
        if source_file
          file_hash = FileHash.compute(source_file)
          specifics[:file_hash] = file_hash if file_hash
        end

        specifics
      end

      # Build language specifics for CLASS
      # @param klass [Class] The class
      # @return [Hash] Language-specific metadata
      def self.build_class_language_specifics(klass)
        specifics = {}

        # Superclass (exclude Object and BasicObject)
        if klass.superclass && klass.superclass != Object && klass.superclass != BasicObject
          specifics[:superclass] = klass.superclass.name
        end

        # Included modules (exclude common ones)
        included = klass.included_modules.map(&:name).reject do |name|
          name.nil? || name.start_with?('Kernel', 'PP::', 'JSON::', 'Enumerable', 'Comparable')
        end
        specifics[:included_modules] = included unless included.empty?

        # Prepended modules
        prepended = klass.ancestors.take_while { |a| a != klass }.map(&:name).compact
        specifics[:prepended_modules] = prepended unless prepended.empty?

        specifics
      rescue
        {}
      end

      # Extract nested classes within a module
      # @param mod [Module] The module
      # @return [Array<Scope>] Nested class scopes
      def self.extract_nested_classes(mod)
        scopes = []

        mod.constants(false).each do |const_name|
          const_value = mod.const_get(const_name)
          next unless const_value.is_a?(Class)

          # Extract nested class
          class_scope = extract_class_scope(const_value)
          scopes << class_scope if class_scope
        rescue => e
          Datadog.logger.debug("SymDB: Failed to extract constant #{mod.name}::#{const_name}: #{e.class}: #{e}")
        end

        scopes
      rescue => e
        Datadog.logger.debug("SymDB: Failed to extract nested classes from #{mod.name}: #{e.class}: #{e}")
        []
      end

      # Extract MODULE-level symbols (constants, module functions)
      # @param mod [Module] The module
      # @return [Array<Symbol>] Module symbols
      def self.extract_module_symbols(mod)
        symbols = []

        # Constants (STATIC_FIELD)
        mod.constants(false).each do |const_name|
          const_value = mod.const_get(const_name)
          # Skip classes (they're scopes, not symbols)
          next if const_value.is_a?(Module)

          symbols << Symbol.new(
            symbol_type: 'STATIC_FIELD',
            name: const_name.to_s,
            line: 0,  # Unknown line, available in entire module
            type: const_value.class.name
          )
        rescue
          # Skip constants that can't be accessed
        end

        symbols
      rescue => e
        Datadog.logger.debug("SymDB: Failed to extract module symbols from #{mod.name}: #{e.class}: #{e}")
        []
      end

      # Extract CLASS-level symbols (class variables, constants)
      # @param klass [Class] The class
      # @return [Array<Symbol>] Class symbols
      def self.extract_class_symbols(klass)
        symbols = []

        # Class variables (STATIC_FIELD)
        klass.class_variables(false).each do |var_name|
          symbols << Symbol.new(
            symbol_type: 'STATIC_FIELD',
            name: var_name.to_s,
            line: 0
          )
        end

        # Constants (STATIC_FIELD) - excluding nested classes
        klass.constants(false).each do |const_name|
          const_value = klass.const_get(const_name)
          next if const_value.is_a?(Module)  # Skip classes/modules

          symbols << Symbol.new(
            symbol_type: 'STATIC_FIELD',
            name: const_name.to_s,
            line: 0,
            type: const_value.class.name
          )
        rescue
          # Skip inaccessible constants
        end

        symbols
      rescue => e
        Datadog.logger.debug("SymDB: Failed to extract class symbols from #{klass.name}: #{e.class}: #{e}")
        []
      end

      # Extract method scopes from a class
      # @param klass [Class] The class
      # @return [Array<Scope>] Method scopes
      def self.extract_method_scopes(klass)
        scopes = []

        # Get all instance methods (public, protected, private)
        all_instance_methods = klass.instance_methods(false) +
          klass.protected_instance_methods(false) +
          klass.private_instance_methods(false)
        all_instance_methods.uniq!

        all_instance_methods.each do |method_name|
          method_scope = extract_method_scope(klass, method_name, :instance)
          scopes << method_scope if method_scope
        end

        # Class methods (singleton methods on the class object)
        klass.singleton_methods(false).each do |method_name|
          method_scope = extract_singleton_method_scope(klass, method_name)
          scopes << method_scope if method_scope
        end

        scopes
      rescue => e
        Datadog.logger.debug("SymDB: Failed to extract methods from #{klass.name}: #{e.class}: #{e}")
        []
      end

      # Extract a single method scope
      # @param klass [Class] The class
      # @param method_name [Symbol] Method name
      # @param method_type [Symbol] :instance or :class
      # @return [Scope, nil] Method scope or nil
      def self.extract_method_scope(klass, method_name, method_type)
        method = klass.instance_method(method_name)
        location = method.source_location

        return nil unless location  # Skip methods without source location

        source_file, line = location

        Scope.new(
          scope_type: 'METHOD',
          name: method_name.to_s,
          source_file: source_file,
          start_line: line,
          end_line: line,  # Ruby doesn't provide end line
          language_specifics: {
            visibility: method_visibility(klass, method_name),
            method_type: method_type.to_s,
            arity: method.arity
          },
          symbols: extract_method_parameters(method)
        )
      rescue => e
        Datadog.logger.debug("SymDB: Failed to extract method #{klass.name}##{method_name}: #{e.class}: #{e}")
        nil
      end

      # Extract a singleton method scope
      # @param klass [Class] The class
      # @param method_name [Symbol] Method name
      # @return [Scope, nil] Method scope or nil
      def self.extract_singleton_method_scope(klass, method_name)
        method = klass.method(method_name)
        location = method.source_location

        return nil unless location

        source_file, line = location

        Scope.new(
          scope_type: 'METHOD',
          name: "self.#{method_name}",
          source_file: source_file,
          start_line: line,
          end_line: line,
          language_specifics: {
            visibility: 'public',  # Singleton methods are public
            method_type: 'class',
            arity: method.arity
          },
          symbols: extract_singleton_method_parameters(method)
        )
      rescue => e
        Datadog.logger.debug("SymDB: Failed to extract singleton method #{klass.name}.#{method_name}: #{e.class}: #{e}")
        nil
      end

      # Get method visibility
      # @param klass [Class] The class
      # @param method_name [Symbol] Method name
      # @return [String] 'public', 'private', or 'protected'
      def self.method_visibility(klass, method_name)
        if klass.private_instance_methods(false).include?(method_name)
          'private'
        elsif klass.protected_instance_methods(false).include?(method_name)
          'protected'
        else
          'public'
        end
      end

      # Extract method parameters as symbols
      # @param method [UnboundMethod] The method
      # @return [Array<Symbol>] Parameter symbols
      def self.extract_method_parameters(method)
        # DIAGNOSTIC: Always log parameter extraction attempts to stderr
        method_name = begin
          method.name
        rescue
          'unknown'
        end

        params = method.parameters
        $stderr.puts "[SymDB] extract_method_parameters: method=#{method_name} params=#{params.inspect}"

        if params.nil?
          $stderr.puts "[SymDB] params is NIL for #{method_name}"
          Datadog.logger.debug("SymDB: method.parameters returned nil for #{begin
            method.name
          rescue
            'unknown'
          end}")
          return []
        end

        if params.empty?
          $stderr.puts "[SymDB] params is EMPTY for #{method_name}"
          Datadog.logger.debug("SymDB: method.parameters returned empty for #{begin
            method.name
          rescue
            'unknown'
          end}")
          return []
        end

        result = params.filter_map do |param_type, param_name|
          # Skip block parameters for MVP
          if param_type == :block
            $stderr.puts "[SymDB] Skipping block param for #{method_name}"
            next
          end
          # Skip if param_name is nil (defensive)
          if param_name.nil?
            $stderr.puts "[SymDB] param_name is NIL, type=#{param_type} for #{method_name}"
            Datadog.logger.debug("SymDB: param_name is nil for #{begin
              method.name
            rescue
              'unknown'
            end}, param_type: #{param_type}")
            next
          end

          Symbol.new(
            symbol_type: 'ARG',
            name: param_name.to_s,
            line: 0  # Parameters available in entire method
          )
        end

        $stderr.puts "[SymDB] Extracted #{result.size} symbols from #{params.size} params for #{method_name}"

        if result.empty? && !params.empty?
          $stderr.puts "[SymDB] WARNING: All params filtered out! params=#{params.inspect}"
          Datadog.logger.debug("SymDB: Extracted #{result.size} parameters from #{begin
            method.name
          rescue
            'unknown'
          end} (params: #{params.inspect})")
        end

        result
      rescue => e
        $stderr.puts "[SymDB] EXCEPTION: #{e.class}: #{e}"
        Datadog.logger.debug("SymDB: Failed to extract parameters from #{begin
          method.name
        rescue
          'unknown'
        end}: #{e.class}: #{e}\n#{e.backtrace.first(5).join("\n")}")
        []
      end

      # Extract singleton method parameters
      # @param method [Method] The singleton method
      # @return [Array<Symbol>] Parameter symbols
      def self.extract_singleton_method_parameters(method)
        params = method.parameters

        if params.nil?
          Datadog.logger.debug("SymDB: method.parameters returned nil for singleton #{begin
            method.name
          rescue
            'unknown'
          end}")
          return []
        end

        if params.empty?
          Datadog.logger.debug("SymDB: method.parameters returned empty for singleton #{begin
            method.name
          rescue
            'unknown'
          end}")
          return []
        end

        result = params.filter_map do |param_type, param_name|
          next if param_type == :block
          # Skip if param_name is nil (defensive)
          if param_name.nil?
            Datadog.logger.debug("SymDB: param_name is nil for singleton #{begin
              method.name
            rescue
              'unknown'
            end}, param_type: #{param_type}")
            next
          end

          Symbol.new(
            symbol_type: 'ARG',
            name: param_name.to_s,
            line: 0
          )
        end

        if result.empty? && !params.empty?
          Datadog.logger.debug("SymDB: Extracted #{result.size} parameters from singleton #{begin
            method.name
          rescue
            'unknown'
          end} (params: #{params.inspect})")
        end

        result
      rescue => e
        Datadog.logger.debug("SymDB: Failed to extract singleton method parameters from #{begin
          method.name
        rescue
          'unknown'
        end}: #{e.class}: #{e}\n#{e.backtrace.first(5).join("\n")}")
        []
      end

      # @api private
      private_class_method :user_code_module?, :user_code_path?, :find_source_file,
        :extract_module_scope, :extract_class_scope,
        :calculate_class_line_range, :build_module_language_specifics,
        :build_class_language_specifics, :extract_nested_classes,
        :extract_module_symbols, :extract_class_symbols,
        :extract_method_scopes, :extract_method_scope,
        :extract_singleton_method_scope, :method_visibility,
        :extract_method_parameters, :extract_singleton_method_parameters
    end
  end
end
