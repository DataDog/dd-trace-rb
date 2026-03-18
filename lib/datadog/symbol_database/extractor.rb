# frozen_string_literal: true

require_relative 'scope'
require_relative 'symbol'
require_relative 'file_hash'
require_relative '../core/utils/array'

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
      # Common Ruby core modules to exclude from included_modules extraction.
      # These are ubiquitous mix-ins that don't provide meaningful context about the class structure.
      # Kernel: Mixed into Object, appears in nearly all classes
      # PP: Pretty-printing module, loaded by many tools
      # JSON: JSON serialization module, loaded by many tools
      # Enumerable: Core iteration protocol, extremely common
      # Comparable: Core comparison protocol, extremely common
      EXCLUDED_COMMON_MODULES = ['Kernel', 'PP::', 'JSON::', 'Enumerable', 'Comparable'].freeze

      # Extract symbols from a module or class.
      # Returns nil if module should be skipped (anonymous, gem code, stdlib).
      #
      # ALL user classes (including namespaced ones like ApplicationCable::Channel) are
      # extracted as root-level MODULE scopes wrapping a CLASS scope. The backend requires
      # root-level scopes to be MODULE/JAR/ASSEMBLY/PACKAGE — a bare CLASS at root throws
      # IllegalArgumentException in mergeRootScopesWithSameName, silently dropping the batch.
      #
      # Namespaced classes (e.g. ApplicationCable::Channel) also appear as nested CLASS scopes
      # inside their parent MODULE scope via extract_nested_classes — that is intentional.
      # The standalone root MODULE(ApplicationCable::Channel) ensures the class is findable
      # by name in search even when the parent namespace module is not extractable (e.g. it
      # has no methods of its own). The duplication is harmless: mergeRootScopesWithSameName
      # merges root scopes with identical names, and DI only needs the class to be findable.
      #
      # @param mod [Module, Class] The module or class to extract from
      # @return [Scope, nil] Extracted scope with nested scopes/symbols, or nil if filtered out
      def self.extract(mod)
        return nil unless mod.is_a?(Module)
        # Use safe name lookup — some classes override the singleton `name` method
        # (e.g. Faker::Travel::Airport defines `def name(size:, region:)` in class << self,
        # which shadows Module#name and raises ArgumentError when called without args).
        mod_name = Module.instance_method(:name).bind(mod).call rescue nil
        return nil unless mod_name  # Skip anonymous modules/classes

        return nil unless user_code_module?(mod)

        if mod.is_a?(Class)
          # Wrap in MODULE scope — backend requires root-level scopes to be MODULE/JAR/ASSEMBLY/PACKAGE.
          # A bare CLASS at the top level causes IllegalArgumentException in the backend's
          # mergeRootScopesWithSameName, silently dropping the entire batch.
          class_scope = extract_class_scope(mod)
          wrap_class_in_module_scope(mod, class_scope)
        else
          extract_module_scope(mod)
        end
      rescue => e
        # Use Module#name safely in rescue block (mod.name might be overridden)
        mod_name = begin
          Module.instance_method(:name).bind(mod).call
        rescue
          '<unknown>'
        end
        Datadog.logger.debug("SymDB: Failed to extract #{mod_name}: #{e.class}: #{e}")
        nil
      end

      # Check if module is from user code (not gems or stdlib)
      # @param mod [Module] The module to check
      # @return [Boolean] true if user code
      def self.user_code_module?(mod)
        # Get module name safely (some modules override .name method like REXML::Functions)
        begin
          mod_name = Module.instance_method(:name).bind(mod).call
        rescue
          return false  # Can't get name safely, skip it
        end

        return false unless mod_name

        # CRITICAL: Exclude entire Datadog namespace (prevents circular extraction)
        # Matches Java: className.startsWith("com/datadog/")
        # Matches Python: packages.is_user_code() excludes ddtrace.*
        return false if mod_name.start_with?('Datadog::')

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
        # Exclude Datadog's own library code (e.g., monkey-patched methods from tracing contrib).
        # Without this, stdlib classes like Net::HTTP appear as user code when dd-trace-rb
        # instruments them, because the patched method source points to lib/datadog/tracing/contrib/.
        return false if path.include?('/lib/datadog/')

        true
      end

      # Find source file for a module.
      # Prefers user code paths over gem/stdlib paths. ActiveRecord models have
      # generated methods (autosave callbacks) whose source is in the gem, but
      # user-defined methods point to app/models/. Without this preference,
      # AR models get filtered out as gem code.
      #
      # For namespace-only modules (no instance or singleton methods), falls back to
      # Module#const_source_location (Ruby 2.7+) to locate the module via its constants.
      # This handles patterns like `module ApplicationCable; class Channel...; end; end`
      # where the namespace module itself has no methods but defines user-code classes.
      #
      # @param mod [Module] The module
      # @return [String, nil] Source file path or nil
      def self.find_source_file(mod)
        fallback = nil

        # Try instance methods first
        mod.instance_methods(false).each do |method_name|
          method = mod.instance_method(method_name)
          location = method.source_location
          next unless location

          path = location[0]
          return path if user_code_path?(path)

          fallback ||= path
        end

        # Try singleton methods
        mod.singleton_methods(false).each do |method_name|
          method = mod.method(method_name)
          location = method.source_location
          next unless location

          path = location[0]
          return path if user_code_path?(path)

          fallback ||= path
        end

        # For namespace-only modules (no methods), try const_source_location (Ruby 2.7+).
        # This handles `module Foo; class Bar...; end; end` where Foo has no methods.
        # Guarded by respond_to? for Ruby 2.5/2.6 compatibility.
        if fallback.nil? && mod.respond_to?(:const_source_location)
          mod.constants(false).each do |const_name|
            location = mod.const_source_location(const_name) rescue nil
            next unless location && !location.empty?

            path = location[0]
            next unless path && !path.empty?

            return path if user_code_path?(path)

            fallback ||= path
          end
        end

        fallback
      rescue
        # Rescue handles: NameError (anonymous module/class), NoMethodError (missing methods),
        # SecurityError (restricted access), or other runtime errors during introspection.
        nil
      end

      # Wrap a CLASS scope in a PACKAGE scope for root-level upload.
      #
      # INTERIM: The backend ROOT_SCOPES constraint ({JAR, ASSEMBLY, MODULE, PACKAGE})
      # does not yet include CLASS. A bare CLASS at root throws IllegalArgumentException
      # in mergeRootScopesWithSameName. Until debugger-backend#1976 merges (adding CLASS
      # to ROOT_SCOPES), we wrap each class in a PACKAGE scope.
      #
      # PACKAGE is used rather than MODULE because Ruby has an actual `module` keyword —
      # uploading `class User` as MODULE: User misrepresents the type and creates confusing
      # duplicate results in DI search ("Module: User" and "Class: User" for the same class).
      # PACKAGE has no conflicting meaning in Ruby.
      #
      # TODO: After debugger-backend#1976 merges, remove this wrapper. Upload CLASS directly
      # at root by changing the `extract` method to call `extract_class_scope` without
      # wrapping, and delete this method.
      #
      # @param klass [Class] The class being wrapped
      # @param class_scope [Scope] The already-extracted CLASS scope
      # @return [Scope] PACKAGE scope wrapping the CLASS scope
      def self.wrap_class_in_module_scope(klass, class_scope)
        source_file = class_scope.source_file
        # steep:ignore:start
        Scope.new(
          scope_type: 'PACKAGE',
          name: klass.name,
          source_file: source_file,
          start_line: SymbolDatabase::UNKNOWN_MIN_LINE,
          end_line: SymbolDatabase::UNKNOWN_MAX_LINE,
          language_specifics: build_module_language_specifics(klass, source_file),
          scopes: [class_scope]
        )
        # steep:ignore:end
      end

      # Extract MODULE scope
      # @param mod [Module] The module
      # @return [Scope] The module scope
      def self.extract_module_scope(mod)
        source_file = find_source_file(mod)

        # steep:ignore:start
        Scope.new(
          scope_type: 'MODULE',
          name: mod.name,
          source_file: source_file,
          start_line: SymbolDatabase::UNKNOWN_MIN_LINE,
          end_line: SymbolDatabase::UNKNOWN_MAX_LINE,
          language_specifics: build_module_language_specifics(mod, source_file),
          scopes: extract_nested_classes(mod),
          symbols: extract_module_symbols(mod)
        )
        # steep:ignore:end
      end

      # Extract CLASS scope
      # @param klass [Class] The class
      # @return [Scope] The class scope
      def self.extract_class_scope(klass)
        methods = klass.instance_methods(false)
        start_line, end_line = calculate_class_line_range(klass, methods)
        source_file = find_source_file(klass)

        # steep:ignore:start
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
        # steep:ignore:end
      end

      # Calculate class line range from method locations
      # @param klass [Class] The class
      # @param methods [Array<Symbol>] Method names
      # @return [Array<Integer, Integer>] [start_line, end_line]
      def self.calculate_class_line_range(klass, methods)
        lines = Core::Utils::Array.filter_map(methods) do |method_name|
          method = klass.instance_method(method_name)
          location = method.source_location
          location[1] if location && location[0]
        end

        return [SymbolDatabase::UNKNOWN_MIN_LINE, SymbolDatabase::UNKNOWN_MAX_LINE] if lines.empty?

        [lines.min, lines.max]
      rescue
        [SymbolDatabase::UNKNOWN_MIN_LINE, SymbolDatabase::UNKNOWN_MAX_LINE]
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

        # Superclass chain (exclude Object and BasicObject).
        # Emitted as an array named super_classes — consistent with Java, .NET, and Python.
        # Array allows for multiple entries if future Ruby versions or mixins expand the chain.
        if klass.superclass && klass.superclass != Object && klass.superclass != BasicObject
          # steep:ignore:start
          specifics[:super_classes] = [klass.superclass.name]
          # steep:ignore:end
        end

        # Included modules (exclude common ones)
        included = klass.included_modules.map(&:name).reject do |name|
          name.nil? || EXCLUDED_COMMON_MODULES.any? { |prefix| name.start_with?(prefix) }
        end
        specifics[:included_modules] = included unless included.empty?

        # Prepended modules
        # Take all ancestors before the class itself (prepending inserts modules before the class in ancestor chain).
        # This code path is taken when a class has prepended modules (e.g., class Foo; prepend Bar; end).
        # Test coverage: spec/datadog/symbol_database/extractor_spec.rb tests prepend behavior.
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
            line: SymbolDatabase::UNKNOWN_MIN_LINE,  # Available in entire module
            type: const_value.class.name
          )
        rescue
          # Skip constants that can't be accessed due to:
          # - NameError: constant removed or not yet defined (race condition during loading)
          # - LoadError: constant triggers autoload that fails
          # - NoMethodError: constant value doesn't respond to expected methods
          # - SecurityError: restricted access in safe mode
          # - Circular dependency errors during const_get
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
            line: SymbolDatabase::UNKNOWN_MIN_LINE
          )
        end

        # Constants (STATIC_FIELD) - excluding nested classes
        klass.constants(false).each do |const_name|
          const_value = klass.const_get(const_name)
          next if const_value.is_a?(Module)  # Skip classes/modules

          symbols << Symbol.new(
            symbol_type: 'STATIC_FIELD',
            name: const_name.to_s,
            line: SymbolDatabase::UNKNOWN_MIN_LINE,
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
        # Method name extraction can fail for exotic methods (e.g., dynamically defined via define_method
        # with unusual names, or methods on singleton classes with overridden #name).
        # Even without a name, we still extract parameter information - it's valuable for analysis.
        # The 'unknown' fallback is only used for debug logging, not in the Symbol payload.
        method_name = begin
          method.name.to_s
        rescue
          'unknown'
        end
        params = method.parameters

        if params.nil?
          Datadog.logger.debug("SymDB: method.parameters returned nil for #{method_name}")
          return []
        end

        if params.empty?
          Datadog.logger.debug("SymDB: method.parameters returned empty for #{method_name}")
          return []
        end

        result = Core::Utils::Array.filter_map(params) do |param_type, param_name|
          # Skip block parameters for MVP
          next if param_type == :block

          # Skip if param_name is nil (defensive)
          if param_name.nil?
            Datadog.logger.debug("SymDB: param_name is nil for #{method_name}, param_type: #{param_type}")
            next
          end

          Symbol.new(
            symbol_type: 'ARG',
            name: param_name.to_s,
            line: SymbolDatabase::UNKNOWN_MIN_LINE,  # Parameters available in entire method
          )
        end

        if result.empty? && !params.empty?
          Datadog.logger.debug("SymDB: Extracted 0 parameters from #{method_name} (params: #{params.inspect})")
        end

        result
      rescue => e
        Datadog.logger.debug("SymDB: Failed to extract parameters from #{method_name}: #{e.class}: #{e}")
        []
      end

      # Extract singleton method parameters
      # @param method [Method] The singleton method
      # @return [Array<Symbol>] Parameter symbols
      def self.extract_singleton_method_parameters(method)
        method_name = begin
          method.name.to_s
        rescue
          'unknown'
        end
        params = method.parameters

        if params.nil?
          Datadog.logger.debug("SymDB: method.parameters returned nil for singleton #{method_name}")
          return []
        end

        if params.empty?
          Datadog.logger.debug("SymDB: method.parameters returned empty for singleton #{method_name}")
          return []
        end

        result = Core::Utils::Array.filter_map(params) do |param_type, param_name|
          # Skip block parameters for MVP
          next if param_type == :block

          # Skip if param_name is nil (defensive)
          if param_name.nil?
            Datadog.logger.debug("SymDB: param_name is nil for singleton #{method_name}, param_type: #{param_type}")
            next
          end

          Symbol.new(
            symbol_type: 'ARG',
            name: param_name.to_s,
            line: SymbolDatabase::UNKNOWN_MIN_LINE,
          )
        end

        if result.empty? && !params.empty?
          Datadog.logger.debug("SymDB: Extracted 0 parameters from singleton #{method_name} (params: #{params.inspect})")
        end

        result
      rescue => e
        Datadog.logger.debug("SymDB: Failed to extract singleton method parameters from #{method_name}: #{e.class}: #{e}\n#{e.backtrace.first(5).join("\n")}")
        []
      end

      # @api private
      private_class_method :user_code_module?, :user_code_path?, :find_source_file,
        :wrap_class_in_module_scope, :extract_module_scope, :extract_class_scope,
        :calculate_class_line_range, :build_module_language_specifics,
        :build_class_language_specifics, :extract_nested_classes,
        :extract_module_symbols, :extract_class_symbols,
        :extract_method_scopes, :extract_method_scope,
        :extract_singleton_method_scope, :method_visibility,
        :extract_method_parameters, :extract_singleton_method_parameters
    end
  end
end
