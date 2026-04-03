# frozen_string_literal: true

require_relative 'scope'
require_relative 'symbol'
require_relative 'file_hash'
require_relative '../core/utils/array'

module Datadog
  module SymbolDatabase
    # Extracts symbol metadata from loaded Ruby modules and classes via introspection.
    #
    # Instance created by Component with injected dependencies (logger, settings,
    # telemetry). All methods are instance methods accessing @logger, @settings,
    # @telemetry directly — no parameter threading needed.
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
    # Produces: Scope objects passed to ScopeBatcher for batching
    # File hashing: Calls FileHash.compute for MODULE scopes
    #
    # Error handling strategy (defense-in-depth):
    #
    # The extractor introspects arbitrary Ruby objects via ObjectSpace. Ruby's
    # reflection APIs (Module#name, #instance_methods, #const_get, #source_location,
    # #parameters) can fail unpredictably on third-party code: NameError from removed
    # constants, LoadError from autoload, ArgumentError from overridden #name methods,
    # SecurityError in restricted contexts, and more.
    #
    # Rescue blocks are organized in three layers:
    #
    # 1. **Inner per-item rescues** (bare `rescue` in const_get loops, method.name):
    #    Skip one constant or name lookup without aborting the enclosing collection.
    #    These are expected failures — no logging needed.
    #
    # 2. **Method-level rescues** (`rescue => e` with logging):
    #    Catch failures in extract_method_scope, find_source_file, etc. Log at debug
    #    for post-hoc diagnosis, return nil or empty array. One bad method/module
    #    doesn't kill the entire class extraction.
    #
    # 3. **Top-level entry rescues** (`rescue => e` with logging + telemetry):
    #    extract() and extract_all() are the error boundaries. Any exception that
    #    escapes layers 1-2 is caught here, logged, and tracked via telemetry.
    #    These are the only rescue blocks that increment telemetry counters.
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
      # Sentinel for unknown minimum line number. 0 means "available throughout the scope."
      # Defined here (the only runtime consumer) so extractor.rb is self-contained.
      # The parent module (lib/datadog/symbol_database.rb) defines the same values for
      # documentation and external reference, but is not required by this file.
      UNKNOWN_MIN_LINE = 0
      # PostgreSQL signed INT_MAX (2^31 - 1). Means "entire file" or "unknown end."
      UNKNOWN_MAX_LINE = 2147483647

      EXCLUDED_COMMON_MODULES = ['Kernel', 'PP::', 'JSON::', 'Enumerable', 'Comparable'].freeze

      # RubyVM::InstructionSequence#trace_points event types included when
      # computing injectable lines on METHOD scopes.
      # :line — any line with executable bytecode (primary line probe target)
      # :return — last expression before method returns (DI instruments return events)
      # :call excluded — method entry is handled by method probes, not line probes
      INJECTABLE_LINE_EVENTS = [:line, :return].freeze

      # @param logger [Logger] Logger instance (SymbolDatabase::Logger facade or compatible)
      # @param settings [Configuration::Settings] Tracer settings
      # @param telemetry [Telemetry, nil] Optional telemetry for metrics
      def initialize(logger:, settings:, telemetry: nil)
        @logger = logger
        @settings = settings
        @telemetry = telemetry
      end

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
      def extract(mod)
        return nil unless mod.is_a?(Module)
        mod_name = safe_mod_name(mod)
        return nil unless mod_name

        return nil unless user_code_module?(mod)

        source_file = find_source_file(mod)
        return nil unless source_file

        inner_scope = if mod.is_a?(Class)
          extract_class_scope(mod)
        else
          extract_module_scope(mod)
        end

        wrap_in_file_scope(source_file, [inner_scope])
      rescue => e
        mod_name = safe_mod_name(mod) || '<unknown>'
        @logger.debug { "symdb: failed to extract #{mod_name}: #{e.class}: #{e}" }
        @telemetry&.inc('tracers', 'symbol_database.extract_error', 1)
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
      # @return [Array<Scope>] Array of FILE scopes
      def extract_all
        entries = collect_extractable_modules
        file_trees = build_file_trees(entries)
        convert_trees_to_scopes(file_trees)
      rescue => e
        @logger.debug { "symdb: error in extract_all: #{e.class}: #{e}" }
        @telemetry&.inc('tracers', 'symbol_database.extract_all_error', 1)
        []
      end

      private

      # Safe Module#name lookup — some classes override the singleton `name` method
      # (e.g. Faker::Travel::Airport defines `def name(size:, region:)` in class << self,
      # which shadows Module#name and raises ArgumentError when called without args).
      # @param mod [Module] The module
      # @return [String, nil] Module name or nil
      def safe_mod_name(mod)
        Module.instance_method(:name).bind(mod).call
      rescue => e
        @logger.debug { "symdb: safe_mod_name failed: #{e.class}: #{e}" }
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
      # @return [Array<Scope>] Array of FILE scopes
      def extract_all
        entries = collect_extractable_modules
        file_trees = build_file_trees(entries)
        convert_trees_to_scopes(file_trees)
      rescue => e
        @logger.debug { "symdb: error in extract_all: #{e.class}: #{e}" }
        @telemetry&.inc('tracers', 'symbol_database.extract_all_error', 1)
        []
      end

      private

      # Whether to include class methods (def self.foo) in extraction.
      # Read from settings on each call so it tracks config changes.
      def upload_class_methods?
        @settings.symbol_database.internal.upload_class_methods
      end

      # Safe Module#name lookup — some classes override the singleton `name` method
      # (e.g. Faker::Travel::Airport defines `def name(size:, region:)` in class << self,
      # which shadows Module#name and raises ArgumentError when called without args).
      # @param mod [Module] The module
      # @return [String, nil] Module name or nil
      def safe_mod_name(mod)
        Module.instance_method(:name).bind(mod).call
      rescue => e
        @logger.debug { "symdb: safe_mod_name failed: #{e.class}: #{e}" }
        nil
      end

      # Check if module is from user code (not gems or stdlib)
      # @param mod [Module] The module to check
      # @return [Boolean] true if user code
      def user_code_module?(mod)
        mod_name = safe_mod_name(mod)
        return false unless mod_name

        # CRITICAL: Exclude entire Datadog namespace (prevents circular extraction)
        # Matches Java: className.startsWith("com/datadog/")
        # Matches Python: packages.is_user_code() excludes ddtrace.*
        return false if mod_name.start_with?('Datadog::')

        # Exclude Ruby root classes. These are never user code, but
        # find_source_file can return a user-code path for them via
        # const_source_location (top-level constants like User are
        # Object constants, so Object.const_source_location(:User)
        # points to the user's file).
        return false if mod.equal?(Object) || mod.equal?(BasicObject) ||
          mod.equal?(Kernel) || mod.equal?(Module) || mod.equal?(Class)

        source_file = find_source_file(mod)
        return false unless source_file

        user_code_path?(source_file)
      end

      # Check if path is user code
      # @param path [String] File path
      # @return [Boolean] true if user code
      def user_code_path?(path)
        # Only absolute paths are real source files. Pseudo-paths like '<main>',
        # '<internal:...>', '(eval)' are not user code.
        return false unless path.start_with?('/')
        # Only .rb files are Ruby source. Excludes the Ruby binary
        # (/usr/local/bin/ruby), C extensions (.so/.bundle), and other
        # non-source files that appear in method source_location.
        return false unless path.end_with?('.rb')
        # Exclude gem paths
        return false if path.include?('/gems/')
        # Exclude Ruby stdlib
        return false if path.include?('/ruby/')
        return false if path.start_with?('<internal:')
        return false if path.include?('(eval)')
        # Exclude test code (not application code)
        return false if path.include?('/spec/')
        return false if path.include?('/test/')
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
      # On Ruby 2.6 (where const_source_location is unavailable), namespace-only modules
      # and classes whose only methods are generated (e.g., AR models with only associations)
      # may not be found — the extraction silently omits them. This is a graceful degradation:
      # fewer symbols uploaded, no errors.
      #
      # @param mod [Module] The module
      # @return [String, nil] Source file path or nil
      def find_source_file(mod)
        fallback = nil

        # Try instance methods first
        mod.instance_methods(false).each do |method_name|
          method = mod.instance_method(method_name)
          location = method.source_location
          next unless location

          path = location[0]
          return path if user_code_path?(path)

          fallback ||= path # steep:ignore
        end

        # Try singleton methods
        mod.singleton_methods(false).each do |method_name|
          method = mod.method(method_name)
          location = method.source_location
          next unless location

          path = location[0]
          return path if user_code_path?(path)

          fallback ||= path # steep:ignore
        end

        # Try const_source_location (Ruby 2.7+) to find where this class/module is declared.
        # This handles two cases:
        #   1. Classes with no user-defined methods (e.g. AR models with only associations) whose
        #      generated methods point to gem code — we find the `class Foo` declaration instead.
        #   2. Namespace-only modules (`module Foo; class Bar; end; end`) with no methods at all.
        if Module.method_defined?(:const_source_location) && mod.name
          # Look up the class/module by its last name component in its enclosing namespace.
          parts = mod.name.split('::')
          const_name = parts.last
          namespace = if parts.length > 1
            begin
              Object.const_get(parts[0..-2].join('::')) # steep:ignore
            rescue NameError
              nil
            end
          else
            Object
          end

          if namespace
            location = begin
              namespace.const_source_location(const_name)
            rescue => e
              @logger.debug { "symdb: const_source_location(#{const_name}) failed: #{e.class}: #{e}" }
              nil
            end

            if location && !location.empty?
              path = location[0]
              return path if path && !path.empty? && user_code_path?(path)
              fallback ||= ((path && !path.empty?) ? path : nil)
            end
          end

          # Also scan constants defined by mod itself (namespace-only modules).
          mod.constants(false).each do |child_const_name|
            location = begin
              mod.const_source_location(child_const_name)
            rescue => e
              @logger.debug { "symdb: const_source_location(#{child_const_name}) failed: #{e.class}: #{e}" }
              nil
            end
            next unless location && !location.empty?

            path = location[0]
            next unless path && !path.empty?

            return path if user_code_path?(path)

            fallback ||= path
          end
        end

        # Try const_source_location (Ruby 2.7+) to find where this class/module is declared.
        # This handles two cases:
        #   1. Classes with no user-defined methods (e.g. AR models with only associations) whose
        #      generated methods point to gem code — we find the `class Foo` declaration instead.
        #   2. Namespace-only modules (`module Foo; class Bar; end; end`) with no methods at all.
        if Module.method_defined?(:const_source_location) && mod.name
          # Look up the class/module by its last name component in its enclosing namespace.
          parts = mod.name.split('::')
          const_name = parts.last
          namespace = if parts.length > 1
            begin
              Object.const_get(parts[0..-2].join('::')) # steep:ignore
            rescue NameError
              nil
            end
          else
            Object
          end

          if namespace
            location = begin
              namespace.const_source_location(const_name)
            rescue
              nil
            end

            if location && !location.empty?
              path = location[0]
              return path if path && !path.empty? && user_code_path?(path)
              fallback ||= ((path && !path.empty?) ? path : nil)
            end
          end

          # Also scan constants defined by mod itself (namespace-only modules).
          mod.constants(false).each do |child_const_name|
            location = begin
              mod.const_source_location(child_const_name)
            rescue => e
              @logger.debug { "symdb: const_source_location(#{child_const_name}) failed: #{e.class}: #{e}" }
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
      rescue => e
        @logger.debug { "symdb: error finding source file for #{safe_mod_name(mod) || '<unknown>'}: #{e.class}: #{e}" }
        nil
      end

      # Wrap inner scopes in a FILE root scope.
      # FILE is the per-source-file root scope for Ruby uploads, analogous to
      # Python's MODULE-per-file or Java's JAR.
      #
      # @param file_path [String] Source file path
      # @param inner_scopes [Array<Scope>] Child scopes to nest under FILE
      # @return [Scope] FILE scope wrapping the inner scopes
      def wrap_in_file_scope(file_path, inner_scopes)
        file_hash = FileHash.compute(file_path, logger: @logger)
        lang = {}
        lang[:file_hash] = file_hash if file_hash

        Scope.new(
          scope_type: 'FILE',
          name: file_path,
          source_file: file_path,
          start_line: UNKNOWN_MIN_LINE,
          end_line: UNKNOWN_MAX_LINE,
          language_specifics: lang,
          scopes: inner_scopes
        )
      end

      # Extract MODULE scope (without file_hash — that belongs on the FILE root scope).
      # Does not include nested classes — nesting is handled by extract_all via FQN splitting.
      # @param mod [Module] The module
      # @return [Scope] The module scope
      def extract_module_scope(mod)
        source_file = find_source_file(mod)

        # steep:ignore:start
        Scope.new(
          scope_type: 'MODULE',
          name: mod.name,
          source_file: source_file,
          start_line: UNKNOWN_MIN_LINE,
          end_line: UNKNOWN_MAX_LINE,
          symbols: extract_module_symbols(mod)
        )
        # steep:ignore:end
      end

      # Extract CLASS scope
      # @param klass [Class] The class
      # @return [Scope] The class scope
      def extract_class_scope(klass)
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
      def calculate_class_line_range(klass, methods)
        lines = Core::Utils::Array.filter_map(methods) do |method_name|
          method = klass.instance_method(method_name)
          location = method.source_location
          location[1] if location && location[0]
        end

        return [UNKNOWN_MIN_LINE, UNKNOWN_MAX_LINE] if lines.empty?

        [lines.min, lines.max]
      rescue => e
        @logger.debug { "symdb: error calculating line range for #{klass.name}: #{e.class}: #{e}" }
        [UNKNOWN_MIN_LINE, UNKNOWN_MAX_LINE]
      end

      # Build language specifics for CLASS
      # @param klass [Class] The class
      # @return [Hash] Language-specific metadata
      def build_class_language_specifics(klass)
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
      rescue => e
        @logger.debug { "symdb: error building language specifics for #{klass.name}: #{e.class}: #{e}" }
        {}
      end

      # Extract MODULE-level symbols (constants, module functions)
      # @param mod [Module] The module
      # @return [Array<Symbol>] Module symbols
      def extract_module_symbols(mod)
        symbols = []

        # Constants (STATIC_FIELD)
        mod.constants(false).each do |const_name|
          const_value = mod.const_get(const_name)
          # Skip classes (they're scopes, not symbols)
          next if const_value.is_a?(Module)

          symbols << Symbol.new(
            symbol_type: 'STATIC_FIELD',
            name: const_name.to_s,
            line: UNKNOWN_MIN_LINE,  # Available in entire module
            type: const_value.class.name
          )
        rescue => e
          # Skip constants that can't be accessed due to:
          # - NameError: constant removed or not yet defined (race condition during loading)
          # - LoadError: constant triggers autoload that fails
          # - NoMethodError: constant value doesn't respond to expected methods
          @logger.debug { "symdb: skipping constant #{const_name}: #{e.class}: #{e}" }
          # - SecurityError: restricted access in safe mode
          # - Circular dependency errors during const_get
        end

        symbols
      rescue => e
        @logger.debug { "symdb: failed to extract module symbols from #{mod.name}: #{e.class}: #{e}" }
        []
      end

      # Extract CLASS-level symbols (class variables, constants)
      # @param klass [Class] The class
      # @return [Array<Symbol>] Class symbols
      def extract_class_symbols(klass)
        symbols = []

        # Class variables (STATIC_FIELD)
        klass.class_variables(false).each do |var_name|
          symbols << Symbol.new(
            symbol_type: 'STATIC_FIELD',
            name: var_name.to_s,
            line: UNKNOWN_MIN_LINE
          )
        end

        # Constants (STATIC_FIELD) - excluding nested classes
        klass.constants(false).each do |const_name|
          const_value = klass.const_get(const_name)
          next if const_value.is_a?(Module)  # Skip classes/modules

          symbols << Symbol.new(
            symbol_type: 'STATIC_FIELD',
            name: const_name.to_s,
            line: UNKNOWN_MIN_LINE,
            type: const_value.class.name
          )
        rescue => e
          @logger.debug { "symdb: skipping class constant #{const_name}: #{e.class}: #{e}" }
        end

        symbols
      rescue => e
        @logger.debug { "symdb: failed to extract class symbols from #{klass.name}: #{e.class}: #{e}" }
        []
      end

      # Extract method scopes from a class
      # @param klass [Class] The class
      # @return [Array<Scope>] Method scopes
      def extract_method_scopes(klass)
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

        scopes
      rescue => e
        @logger.debug { "symdb: failed to extract methods from #{klass.name}: #{e.class}: #{e}" }
        []
      end

      # Extract a single method scope
      # @param klass [Class] The class
      # @param method_name [Symbol] Method name
      # @param method_type [Symbol] :instance or :class
      # @return [Scope, nil] Method scope or nil
      def extract_method_scope(klass, method_name, method_type)
        method = klass.instance_method(method_name)
        location = method.source_location

        return nil unless location  # Skip methods without source location

        source_file, line = location
        return nil unless user_code_path?(source_file)  # Skip gem/stdlib methods

        injectable_lines, end_line = extract_injectable_lines(method, line)

        Scope.new(
          scope_type: 'METHOD',
          name: method_name.to_s,
          source_file: source_file,
          start_line: line,
          end_line: end_line,
          injectible_lines: injectable_lines,
          language_specifics: {
            visibility: method_visibility(klass, method_name),
            method_type: method_type.to_s,
            arity: method.arity
          },
          symbols: extract_method_parameters(method, method_type)
        )
      rescue => e
        @logger.debug { "symdb: failed to extract method #{klass.name}##{method_name}: #{e.class}: #{e}" }
        nil
      end

      # Get method visibility
      # @param klass [Class] The class
      # @param method_name [Symbol] Method name
      # @return [String] 'public', 'private', or 'protected'
      def method_visibility(klass, method_name)
        if klass.private_instance_methods(false).include?(method_name)
          'private'
        elsif klass.protected_instance_methods(false).include?(method_name)
          'protected'
        else
          'public'
        end
      end

      # Extract injectable lines and end_line from a method's bytecode.
      # Returns [ranges, end_line] where ranges is an array of {start:, end:} hashes
      # or nil if iseq is unavailable (C-extension methods).
      # @param method [Method, UnboundMethod] The method
      # @param start_line [Integer] Fallback end_line if iseq unavailable
      # @return [Array(Array<Hash>, Integer), Array(nil, Integer)]
      def extract_injectable_lines(method, start_line)
        iseq = RubyVM::InstructionSequence.of(method) # steep:ignore
        unless iseq
          @logger.debug { "symdb: no iseq for #{method.name} (C extension or native), skipping injectable lines" }
          return [nil, start_line]
        end

        lines = iseq.trace_points
          .select { |_, event| INJECTABLE_LINE_EVENTS.include?(event) }
          .map(&:first)
          .uniq
          .sort

        end_line = lines.max || start_line
        ranges = build_injectable_ranges(lines)
        result = ranges.empty? ? nil : ranges
        @logger.debug { "symdb: #{method.name} injectable lines: #{result ? "#{ranges.size} range(s), lines #{lines.first}..#{lines.last}" : 'none (no matching events)'}" }
        [result, end_line]
      end

      # Compress sorted line numbers into consecutive ranges.
      # [4, 5, 6, 8, 10, 11] => [{start: 4, end: 6}, {start: 8, end: 8}, {start: 10, end: 11}]
      # @param lines [Array<Integer>] Sorted, deduplicated line numbers
      # @return [Array<Hash>] Array of {start:, end:} range hashes
      def build_injectable_ranges(lines)
        return [] if lines.empty?

        ranges = []
        range_start = lines[0]
        prev = range_start

        lines[1..-1].each do |line| # steep:ignore
          if line == prev + 1
            prev = line
          else
            ranges << {start: range_start, end: prev}
            range_start = line
            prev = line
          end
        end
        ranges << {start: range_start, end: prev}
        ranges
      end

      # Extract method parameters as symbols.
      # Does NOT include `self` — Ruby's implicit receiver is not a declared parameter.
      # Java skips slot 0 (this) for the same reason. .NET uploads `this` but the web-ui
      # filters it for dotnet. Ruby follows Java's approach: don't upload it.
      # @param method [UnboundMethod] The method
      # @param method_type [Symbol] :instance or :class (unused, kept for API compatibility)
      # @return [Array<Symbol>] Parameter symbols
      def extract_method_parameters(method, method_type = :instance)
        method_name = begin
          method.name.to_s
        rescue => e
          @logger.debug { "symdb: method.name failed: #{e.class}: #{e}" }
          'unknown'
        end
        params = method.parameters

        return [] if params.nil? || params.empty?

        Core::Utils::Array.filter_map(params) do |param_type, param_name|
          # Skip block parameters for MVP
          next if param_type == :block

          # Skip if param_name is nil — normal for generated methods (attr_writer, attr_accessor).
          # See pitfall 37 and specs/json-schema.md "Discovered During Implementation".
          next if param_name.nil?

          # Skip if param_name is nil — normal for generated methods (attr_writer, attr_accessor).
          # See pitfall 37 and specs/json-schema.md "Discovered During Implementation".
          next if param_name.nil?

          Symbol.new(
            symbol_type: 'ARG',
            name: param_name.to_s,
            line: UNKNOWN_MIN_LINE,  # Parameters available in entire method
          )
        end

        if result.empty? && !params.empty?
          Datadog.logger.debug("SymDB: Extracted 0 parameters from singleton #{method_name} (params: #{params.inspect})")
        end

        result
      rescue => e
        @logger.debug { "symdb: failed to extract parameters from #{method_name}: #{e.class}: #{e}" }
        []
      end

      # ── extract_all helpers ──────────────────────────────────────────────

      # Pass 1: Collect all extractable modules with methods grouped by source file.
      # @return [Hash] { mod_name => { mod:, methods_by_file: { path => [{name:, method:, type:}] } } }
      def collect_extractable_modules
        entries = {}

        ObjectSpace.each_object(Module) do |mod|
          mod_name = safe_mod_name(mod)
          next unless mod_name
          next unless user_code_module?(mod)

          methods_by_file = group_methods_by_file(mod)

          # For modules/classes with no methods but valid source, use find_source_file as fallback.
          # This handles namespace modules and classes with only constants.
          if methods_by_file.empty?
            source_file = find_source_file(mod)
            methods_by_file[source_file] = [] if source_file
          end

          next if methods_by_file.empty?

          entries[mod_name] = {mod: mod, methods_by_file: methods_by_file}
        rescue => e
          @logger.debug { "symdb: error collecting #{mod_name || '<unknown>'}: #{e.class}: #{e}" }
        end

        entries
      end

      # Group a module's methods by their source file path.
      # @param mod [Module] The module
      # @return [Hash] { file_path => [{name:, method:, type:}] }
      def group_methods_by_file(mod)
        result = Hash.new { |h, k| h[k] = [] } # steep:ignore

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

          result[loc[0]] << {name: method_name, method: method, type: :instance}
        rescue => e
          @logger.debug { "symdb: error grouping method #{method_name}: #{e.class}: #{e}" }
        end

        result
      rescue => e
        @logger.debug { "symdb: error grouping methods: #{e.class}: #{e}" }
        {}
      end

      # Pass 2: Build per-file trees from collected entries.
      # Uses hash nodes during construction, converted to Scope objects at the end.
      #
      # Node structure: { name:, type:, children: {name => node}, methods: [], mod:, source_file:, fqn: }
      #
      # @param entries [Hash] Output from collect_extractable_modules
      # @return [Hash] { file_path => root_node }
      def build_file_trees(entries)
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
          @logger.debug { "symdb: error building tree for #{mod_name}: #{e.class}: #{e}" }
        end

        file_trees
      end

      # Place a module/class in the file tree at the correct nesting depth.
      # Creates intermediate namespace nodes as needed.
      def place_in_tree(root, name_parts, mod, methods, file_path)
        current = root

        # Create/find intermediate nodes for each namespace segment except the last
        name_parts[0..-2].each_with_index do |part, idx| # steep:ignore
          fqn = name_parts[0..idx].join('::') # steep:ignore
          current[:children][part] ||= {
            name: fqn, type: resolve_scope_type(fqn),
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
            name: mod.name,
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
      def resolve_scope_type(fqn)
        const = Object.const_get(fqn)
        const.is_a?(Class) ? 'CLASS' : 'MODULE'
      rescue => e
        @logger.debug { "symdb: resolve_scope_type(#{fqn}) failed: #{e.class}: #{e}, defaulting to MODULE" }
        'MODULE'
      end

      # Convert hash-based file trees to Scope objects.
      # @param file_trees [Hash] { file_path => root_node }
      # @return [Array<Scope>] Array of FILE scopes
      def convert_trees_to_scopes(file_trees)
        file_trees.map do |file_path, root|
          file_hash = FileHash.compute(file_path, logger: @logger)
          lang = {}
          lang[:file_hash] = file_hash if file_hash

          Scope.new(
            scope_type: 'FILE',
            name: file_path,
            source_file: file_path,
            start_line: UNKNOWN_MIN_LINE,
            end_line: UNKNOWN_MAX_LINE,
            language_specifics: lang,
            scopes: root[:children].values.map { |child| convert_node_to_scope(child) }
          )
        end
      end

      # Convert a single hash node to a Scope object (recursive).
      # @param node [Hash] Tree node
      # @return [Scope] Scope object
      def convert_node_to_scope(node)
        # Build method scopes from collected method entries
        method_scopes = Core::Utils::Array.filter_map(node[:methods]) do |method_info|
          build_instance_method_scope(node[:mod], method_info[:name], method_info[:method])
        end

        # Recurse into child scopes (nested modules/classes)
        child_scopes = node[:children].values.map { |child| convert_node_to_scope(child) }

        # Compute line range from method start lines
        lines = method_scopes.map(&:start_line).reject { |l| l == UNKNOWN_MIN_LINE } # steep:ignore
        start_line = lines.empty? ? UNKNOWN_MIN_LINE : lines.min
        end_line = lines.empty? ? UNKNOWN_MAX_LINE : lines.max

        # Extract symbols (constants, class variables) if we have the actual module object
        symbols = node[:mod] ? extract_scope_symbols(node[:mod]) : []

        # Build language specifics
        lang = if node[:type] == 'CLASS' && node[:mod]
          build_class_language_specifics(node[:mod])
        else
          {}
        end

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
      end

      # Build a METHOD scope from a pre-resolved instance method.
      # Used by extract_all path where methods are collected in Pass 1.
      # @param klass [Module] The class/module (for visibility lookup)
      # @param method_name [Symbol] Method name
      # @param method [UnboundMethod] The method object
      # @return [Scope, nil] Method scope or nil
      def build_instance_method_scope(klass, method_name, method)
        location = method.source_location
        return nil unless location

        source_file, line = location

        injectable_lines, end_line = extract_injectable_lines(method, line)

        Scope.new(
          scope_type: 'METHOD',
          name: method_name.to_s,
          source_file: source_file,
          start_line: line,
          end_line: end_line,
          injectible_lines: injectable_lines,
          language_specifics: {
            visibility: klass ? method_visibility(klass, method_name) : 'public', # steep:ignore
            method_type: 'instance',
            arity: method.arity
          },
          symbols: extract_method_parameters(method, :instance)
        )
      rescue => e
        klass_name = klass ? (safe_mod_name(klass) || '<unknown>') : '<unknown>'
        @logger.debug { "symdb: failed to build method scope #{klass_name}##{method_name}: #{e.class}: #{e}" }
        nil
      end

      # Extract symbols (constants, class variables) from a module or class.
      # Unified version of extract_module_symbols and extract_class_symbols.
      # @param mod [Module] The module or class
      # @return [Array<Symbol>] Symbols
      def extract_scope_symbols(mod)
        symbols = []

        # Class variables (only for classes)
        if mod.is_a?(Class)
          mod.class_variables(false).each do |var_name|
            symbols << Symbol.new(
              symbol_type: 'STATIC_FIELD',
              name: var_name.to_s,
              line: UNKNOWN_MIN_LINE
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
            line: UNKNOWN_MIN_LINE,
            type: const_value.class.name
          )
        rescue => e
          @logger.debug { "symdb: skipping module constant #{const_name}: #{e.class}: #{e}" }
        end

        symbols
      rescue => e
        mod_name = safe_mod_name(mod) || '<unknown>'
        @logger.debug { "symdb: failed to extract symbols from #{mod_name}: #{e.class}: #{e}" }
        []
      end
    end
  end
end
