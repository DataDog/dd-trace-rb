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

      # Extract symbols from a single module or class.
      # Returns nil if module should be skipped (anonymous, gem code, stdlib).
      #
      # Returns a FILE scope wrapping the extracted CLASS or MODULE scope.
      # The backend requires root-level scopes to be in ROOT_SCOPES (MODULE, JAR,
      # ASSEMBLY, PACKAGE, FILE). FILE is the natural root for Ruby — one per source file.
      #
      # For full extraction with proper FQN-based nesting and per-file method grouping,
      # use extract_all instead. This method is kept for single-module extraction in tests.
      #
      # @param mod [Module, Class] The module or class to extract from
      # @return [Scope, nil] FILE scope wrapping extracted scope, or nil if filtered out
      def self.extract(mod, upload_class_methods: false)
        return nil unless mod.is_a?(Module)
        mod_name = safe_mod_name(mod)
        return nil unless mod_name

        return nil unless user_code_module?(mod)

        source_file = find_source_file(mod)
        return nil unless source_file

        inner_scope = if mod.is_a?(Class)
          extract_class_scope(mod, upload_class_methods: upload_class_methods)
        else
          extract_module_scope(mod)
        end

        wrap_in_file_scope(source_file, [inner_scope])
      rescue => e
        mod_name = safe_mod_name(mod) || '<unknown>'
        Datadog.logger.debug("SymDB: Failed to extract #{mod_name}: #{e.class}: #{e}")
        nil
      end

      # Extract symbols from all loaded modules and classes.
      # Returns an array of FILE scopes with proper FQN-based nesting.
      #
      # Two-pass algorithm:
      # Pass 1: Iterate ObjectSpace, collect all extractable modules with methods grouped by file
      # Pass 2: Build FILE scope trees with nested MODULE/CLASS hierarchy from FQN splitting
      #
      # This is the production path used by Component. Methods are split by source file,
      # so a class reopened across two files produces two FILE scopes, each with only
      # the methods defined in that file.
      #
      # @param upload_class_methods [Boolean] Whether to include singleton methods
      # @return [Array<Scope>] Array of FILE scopes
      def self.extract_all(upload_class_methods: false)
        entries = collect_extractable_modules(upload_class_methods: upload_class_methods)
        file_trees = build_file_trees(entries)
        convert_trees_to_scopes(file_trees)
      rescue => e
        Datadog.logger.debug("SymDB: Error in extract_all: #{e.class}: #{e}")
        []
      end

      # Resolve symlinks in a file path. On macOS, /var is a symlink to /private/var
      # and source_location may return either form. Normalizing ensures consistent
      # FILE scope names for the same physical file.
      # @param path [String] File path
      # @return [String] Resolved path (or original if resolution fails)
      def self.resolve_path(path)
        File.realpath(path)
      rescue
        path
      end

      # Safe Module#name lookup — some classes override the singleton `name` method
      # (e.g. Faker::Travel::Airport defines `def name(size:, region:)` in class << self,
      # which shadows Module#name and raises ArgumentError when called without args).
      # @param mod [Module] The module
      # @return [String, nil] Module name or nil
      def self.safe_mod_name(mod)
        Module.instance_method(:name).bind(mod).call
      rescue
        nil
      end

      # Check if module is from user code (not gems or stdlib)
      # @param mod [Module] The module to check
      # @return [Boolean] true if user code
      def self.user_code_module?(mod)
        mod_name = safe_mod_name(mod)
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
        # Only absolute paths are real source files. Pseudo-paths like '<main>',
        # '<internal:...>', '(eval)' are not user code.
        return false unless path.start_with?('/')
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
            location = begin
              mod.const_source_location(const_name)
            rescue
              nil
            end
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

      # Wrap inner scopes in a FILE root scope.
      # FILE is the per-source-file root scope for Ruby uploads, analogous to
      # Python's MODULE-per-file or Java's JAR.
      #
      # @param file_path [String] Source file path
      # @param inner_scopes [Array<Scope>] Child scopes to nest under FILE
      # @return [Scope] FILE scope wrapping the inner scopes
      def self.wrap_in_file_scope(file_path, inner_scopes)
        file_hash = FileHash.compute(file_path)
        lang = {}
        lang[:file_hash] = file_hash if file_hash

        # steep:ignore:start
        Scope.new(
          scope_type: 'FILE',
          name: file_path,
          source_file: file_path,
          start_line: SymbolDatabase::UNKNOWN_MIN_LINE,
          end_line: SymbolDatabase::UNKNOWN_MAX_LINE,
          language_specifics: lang,
          scopes: inner_scopes
        )
        # steep:ignore:end
      end

      # Extract MODULE scope (without file_hash — that belongs on the FILE root scope).
      # Does not include nested classes — nesting is handled by extract_all via FQN splitting.
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
          symbols: extract_module_symbols(mod)
        )
        # steep:ignore:end
      end

      # Extract CLASS scope
      # @param klass [Class] The class
      # @return [Scope] The class scope
      def self.extract_class_scope(klass, upload_class_methods: false)
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
          scopes: extract_method_scopes(klass, upload_class_methods: upload_class_methods),
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
      def self.extract_method_scopes(klass, upload_class_methods: false)
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

        # Class methods (singleton methods defined with `def self.foo`).
        # Not uploaded by default — Ruby DI cannot instrument class methods
        # because it only prepends to a class's instance method lookup chain,
        # not to the singleton class. Enable with:
        #   settings.symbol_database.internal.upload_class_methods = true
        # See: docs/class_methods_di_design.md
        if upload_class_methods
          klass.singleton_methods(false).each do |method_name|
            method_scope = extract_singleton_method_scope(klass, method_name)
            scopes << method_scope if method_scope
          end
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
          symbols: extract_method_parameters(method, method_type)
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

        # Name is bare method_name (no `self.` prefix) — method_type: 'class'
        # in language_specifics is the standard way to distinguish from instance
        # methods, matching Java/C#/.NET behavior. The `self.` prefix was
        # non-standard and not used by any other tracer.
        Scope.new(
          scope_type: 'METHOD',
          name: method_name.to_s,
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

      # Extract method parameters as symbols.
      # For instance methods, prepends a synthetic `self` ARG — consistent with Java and .NET
      # which always emit the implicit receiver (`this`) as the first ARG. This allows DI
      # expression evaluation to reference `self.field` at a probe point.
      # @param method [UnboundMethod] The method
      # @param method_type [Symbol] :instance or :class
      # @return [Array<Symbol>] Parameter symbols
      def self.extract_method_parameters(method, method_type = :instance)
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

        # Prepend synthetic `self` ARG for instance methods.
        # `self` is implicit in Ruby (not in Method#parameters) but must be registered as
        # an available symbol so DI can evaluate expressions like `self.name` at a probe point.
        self_arg = if method_type == :instance
          [Symbol.new(symbol_type: 'ARG', name: 'self', line: SymbolDatabase::UNKNOWN_MIN_LINE)]
        else
          []
        end

        if params.nil? || params.empty?
          return self_arg
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
        end

        self_arg + result
      rescue => e
        Datadog.logger.debug("SymDB: Failed to extract parameters from #{method_name}: #{e.class}: #{e}")
        self_arg
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

        if params.nil? || params.empty?
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
        end

        result
      rescue => e
        Datadog.logger.debug("SymDB: Failed to extract singleton method parameters from #{method_name}: #{e.class}: #{e}\n#{e.backtrace.first(5).join("\n")}")
        []
      end

      # ── extract_all helpers ──────────────────────────────────────────────

      # Pass 1: Collect all extractable modules with methods grouped by source file.
      # @return [Hash] { mod_name => { mod:, methods_by_file: { path => [{name:, method:, type:}] } } }
      def self.collect_extractable_modules(upload_class_methods:)
        entries = {}

        ObjectSpace.each_object(Module) do |mod|
          mod_name = safe_mod_name(mod)
          next unless mod_name
          next unless user_code_module?(mod)

          methods_by_file = group_methods_by_file(mod, upload_class_methods: upload_class_methods)

          # For modules/classes with no methods but valid source, use find_source_file as fallback.
          # This handles namespace modules and classes with only constants.
          if methods_by_file.empty?
            source_file = find_source_file(mod)
            methods_by_file[resolve_path(source_file)] = [] if source_file
          end

          next if methods_by_file.empty?

          entries[mod_name] = {mod: mod, methods_by_file: methods_by_file}
        rescue => e
          Datadog.logger.debug("SymDB: Error collecting #{mod_name || '<unknown>'}: #{e.class}: #{e}")
        end

        entries
      end

      # Group a module's methods by their source file path.
      # @param mod [Module] The module
      # @param upload_class_methods [Boolean] Whether to include singleton methods
      # @return [Hash] { file_path => [{name:, method:, type:}] }
      def self.group_methods_by_file(mod, upload_class_methods:)
        result = Hash.new { |h, k| h[k] = [] }

        # Instance methods (public, protected, private)
        all_methods = mod.instance_methods(false) +
          mod.protected_instance_methods(false) +
          mod.private_instance_methods(false)
        all_methods.uniq!

        all_methods.each do |method_name|
          method = mod.instance_method(method_name)
          loc = method.source_location
          next unless loc
          next unless user_code_path?(loc[0])

          result[resolve_path(loc[0])] << {name: method_name, method: method, type: :instance}
        rescue => e
          Datadog.logger.debug("SymDB: Error grouping method #{method_name}: #{e.class}: #{e}")
        end

        # Singleton methods (if enabled)
        if upload_class_methods
          mod.singleton_methods(false).each do |method_name|
            method = mod.method(method_name)
            loc = method.source_location
            next unless loc
            next unless user_code_path?(loc[0])

            result[resolve_path(loc[0])] << {name: method_name, method: method, type: :singleton}
          rescue => e
            Datadog.logger.debug("SymDB: Error grouping singleton method #{method_name}: #{e.class}: #{e}")
          end
        end

        result
      rescue => e
        Datadog.logger.debug("SymDB: Error grouping methods: #{e.class}: #{e}")
        {}
      end

      # Pass 2: Build per-file trees from collected entries.
      # Uses hash nodes during construction, converted to Scope objects at the end.
      #
      # Node structure: { name:, type:, children: {name => node}, methods: [], mod:, source_file:, fqn: }
      #
      # @param entries [Hash] Output from collect_extractable_modules
      # @return [Hash] { file_path => root_node }
      def self.build_file_trees(entries)
        file_trees = {}

        # Sort by FQN depth so parents are placed before children.
        # This ensures intermediate nodes created for parents have correct scope_type.
        sorted = entries.sort_by { |name, _| name.count(':') }

        sorted.each do |mod_name, entry|
          entry[:methods_by_file].each do |file_path, methods|
            root = file_trees[file_path] ||= {
              name: file_path, type: 'FILE', children: {},
              methods: [], mod: nil, source_file: file_path, fqn: nil
            }
            parts = mod_name.split('::')
            place_in_tree(root, parts, entry[:mod], methods, file_path)
          end
        rescue => e
          Datadog.logger.debug("SymDB: Error building tree for #{mod_name}: #{e.class}: #{e}")
        end

        file_trees
      end

      # Place a module/class in the file tree at the correct nesting depth.
      # Creates intermediate namespace nodes as needed.
      def self.place_in_tree(root, name_parts, mod, methods, file_path)
        current = root

        # Create/find intermediate nodes for each namespace segment except the last
        name_parts[0..-2].each_with_index do |part, idx|
          fqn = name_parts[0..idx].join('::')
          current[:children][part] ||= {
            name: part, type: resolve_scope_type(fqn),
            children: {}, methods: [], mod: nil,
            source_file: file_path, fqn: fqn
          }
          current = current[:children][part]
        end

        # Create or find the leaf node
        leaf_name = name_parts.last
        leaf = current[:children][leaf_name]
        if leaf
          # Node exists (was created as intermediate or from another entry).
          # Update type and mod — the actual module object is authoritative.
          leaf[:type] = mod.is_a?(Class) ? 'CLASS' : 'MODULE'
          leaf[:mod] = mod
        else
          leaf = {
            name: leaf_name,
            type: mod.is_a?(Class) ? 'CLASS' : 'MODULE',
            children: {}, methods: [],
            mod: mod, source_file: file_path,
            fqn: mod.name
          }
          current[:children][leaf_name] = leaf
        end

        # Add methods for this file
        leaf[:methods].concat(methods)
      end

      # Determine scope type (CLASS or MODULE) for a fully-qualified name.
      # Looks up the actual Ruby constant to check if it's a Class.
      # @param fqn [String] Fully-qualified name (e.g. "Authentication::Strategies")
      # @return [String] 'CLASS' or 'MODULE'
      def self.resolve_scope_type(fqn)
        const = Object.const_get(fqn)
        const.is_a?(Class) ? 'CLASS' : 'MODULE'
      rescue
        'MODULE'
      end

      # Convert hash-based file trees to Scope objects.
      # @param file_trees [Hash] { file_path => root_node }
      # @return [Array<Scope>] Array of FILE scopes
      def self.convert_trees_to_scopes(file_trees)
        file_trees.map do |file_path, root|
          file_hash = FileHash.compute(file_path)
          lang = {}
          lang[:file_hash] = file_hash if file_hash

          # steep:ignore:start
          Scope.new(
            scope_type: 'FILE',
            name: file_path,
            source_file: file_path,
            start_line: SymbolDatabase::UNKNOWN_MIN_LINE,
            end_line: SymbolDatabase::UNKNOWN_MAX_LINE,
            language_specifics: lang,
            scopes: root[:children].values.map { |child| convert_node_to_scope(child) }
          )
          # steep:ignore:end
        end
      end

      # Convert a single hash node to a Scope object (recursive).
      # @param node [Hash] Tree node
      # @return [Scope] Scope object
      def self.convert_node_to_scope(node)
        # Build method scopes from collected method entries
        method_scopes = node[:methods].filter_map do |method_info|
          if method_info[:type] == :singleton
            build_singleton_method_scope(method_info[:method])
          else
            build_instance_method_scope(node[:mod], method_info[:name], method_info[:method])
          end
        end

        # Recurse into child scopes (nested modules/classes)
        child_scopes = node[:children].values.map { |child| convert_node_to_scope(child) }

        # Compute line range from method start lines
        lines = method_scopes.map(&:start_line).reject { |l| l == SymbolDatabase::UNKNOWN_MIN_LINE }
        start_line = lines.empty? ? SymbolDatabase::UNKNOWN_MIN_LINE : lines.min
        end_line = lines.empty? ? SymbolDatabase::UNKNOWN_MAX_LINE : lines.max

        # Extract symbols (constants, class variables) if we have the actual module object
        symbols = node[:mod] ? extract_scope_symbols(node[:mod]) : []

        # Build language specifics
        lang = if node[:type] == 'CLASS' && node[:mod]
          build_class_language_specifics(node[:mod])
        else
          {}
        end

        # steep:ignore:start
        Scope.new(
          scope_type: node[:type],
          name: node[:name],
          source_file: node[:source_file],
          start_line: start_line,
          end_line: end_line,
          language_specifics: lang,
          scopes: method_scopes + child_scopes,
          symbols: symbols
        )
        # steep:ignore:end
      end

      # Build a METHOD scope from a pre-resolved instance method.
      # Used by extract_all path where methods are collected in Pass 1.
      # @param klass [Module] The class/module (for visibility lookup)
      # @param method_name [Symbol] Method name
      # @param method [UnboundMethod] The method object
      # @return [Scope, nil] Method scope or nil
      def self.build_instance_method_scope(klass, method_name, method)
        location = method.source_location
        return nil unless location

        source_file, line = location

        Scope.new(
          scope_type: 'METHOD',
          name: method_name.to_s,
          source_file: source_file,
          start_line: line,
          end_line: line,
          language_specifics: {
            visibility: klass ? method_visibility(klass, method_name) : 'public',
            method_type: 'instance',
            arity: method.arity
          },
          symbols: extract_method_parameters(method, :instance)
        )
      rescue => e
        klass_name = klass ? (safe_mod_name(klass) || '<unknown>') : '<unknown>'
        Datadog.logger.debug("SymDB: Failed to build method scope #{klass_name}##{method_name}: #{e.class}: #{e}")
        nil
      end

      # Build a METHOD scope from a pre-resolved singleton method.
      # @param method [Method] The singleton method object
      # @return [Scope, nil] Method scope or nil
      def self.build_singleton_method_scope(method)
        location = method.source_location
        return nil unless location

        source_file, line = location

        Scope.new(
          scope_type: 'METHOD',
          name: method.name.to_s,
          source_file: source_file,
          start_line: line,
          end_line: line,
          language_specifics: {
            visibility: 'public',
            method_type: 'class',
            arity: method.arity
          },
          symbols: extract_singleton_method_parameters(method)
        )
      rescue => e
        Datadog.logger.debug("SymDB: Failed to build singleton method scope: #{e.class}: #{e}")
        nil
      end

      # Extract symbols (constants, class variables) from a module or class.
      # Unified version of extract_module_symbols and extract_class_symbols.
      # @param mod [Module] The module or class
      # @return [Array<Symbol>] Symbols
      def self.extract_scope_symbols(mod)
        symbols = []

        # Class variables (only for classes)
        if mod.is_a?(Class)
          mod.class_variables(false).each do |var_name|
            symbols << Symbol.new(
              symbol_type: 'STATIC_FIELD',
              name: var_name.to_s,
              line: SymbolDatabase::UNKNOWN_MIN_LINE
            )
          end
        end

        # Constants (excluding nested modules/classes)
        mod.constants(false).each do |const_name|
          const_value = mod.const_get(const_name)
          next if const_value.is_a?(Module)

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
        mod_name = safe_mod_name(mod) || '<unknown>'
        Datadog.logger.debug("SymDB: Failed to extract symbols from #{mod_name}: #{e.class}: #{e}")
        []
      end

      # @api private
      private_class_method :resolve_path, :safe_mod_name, :user_code_module?, :user_code_path?,
        :find_source_file, :wrap_in_file_scope,
        :extract_module_scope, :extract_class_scope,
        :calculate_class_line_range,
        :build_class_language_specifics,
        :extract_module_symbols, :extract_class_symbols,
        :extract_method_scopes, :extract_method_scope,
        :extract_singleton_method_scope, :method_visibility,
        :extract_method_parameters, :extract_singleton_method_parameters,
        :collect_extractable_modules, :group_methods_by_file,
        :build_file_trees, :place_in_tree, :resolve_scope_type,
        :convert_trees_to_scopes, :convert_node_to_scope,
        :build_instance_method_scope, :build_singleton_method_scope,
        :extract_scope_symbols
    end
  end
end
