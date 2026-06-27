# frozen_string_literal: true

require_relative 'scope'
require_relative 'symbol'
require_relative 'file_hash'
require_relative '../core/utils/enumerable_compat'

module Datadog
  module SymbolDatabase
    # Extracts symbol metadata from loaded Ruby modules and classes via introspection.
    #
    # Instance created by Component with injected dependencies (logger, settings).
    # All methods are instance methods accessing @logger, @settings directly —
    # no parameter threading needed.
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
    # 3. **Top-level entry rescues** (`rescue => e` with logging):
    #    extract() and extract_all() are the error boundaries. Any exception that
    #    escapes layers 1-2 is caught here and logged.
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
      # computing targetable lines on METHOD scopes.
      # :line — any line with executable bytecode (primary line probe target)
      # :return — last expression before method returns (DI instruments return events)
      # :call excluded — method entry is handled by method probes, not line probes
      TARGETABLE_LINE_EVENTS = [:line, :return].freeze

      # Cached unbound Module#singleton_class? — dispatched explicitly so user classes
      # that define their own `singleton_class?` (e.g. with required arguments) cannot
      # intercept the predicate and cause the module to be silently dropped from
      # extract_all. Cached at load time because build_per_file_index iterates
      # ObjectSpace.each_object(Module) over tens of thousands of modules.
      MODULE_SINGLETON_CLASS_PRED = Module.instance_method(:singleton_class?)
      private_constant :MODULE_SINGLETON_CLASS_PRED

      # Cached UnboundMethod for Module#name — avoids resolving it on every
      # safe_mod_name call. Some classes override .name (e.g. Faker::Travel::Airport),
      # so we bind the original Module#name to get the real module name safely.
      MODULE_NAME = Module.instance_method(:name)

      # Cached UnboundMethods for the remaining class/module/object introspection
      # used during extraction. Like MODULE_NAME, these bind the original
      # implementations and are dispatched explicitly so that application code
      # which overrides any of them (per-class, on a subclass, or in a singleton
      # class) can neither intercept extraction nor be executed as a side effect
      # of it. KERNEL_CLASS recovers an object's real class without calling a
      # possibly-overridden #class.
      CLASS_SUPERCLASS = Class.instance_method(:superclass)
      MODULE_INCLUDED_MODULES = Module.instance_method(:included_modules)
      MODULE_ANCESTORS = Module.instance_method(:ancestors)
      MODULE_CLASS_VARIABLES = Module.instance_method(:class_variables)
      MODULE_CONSTANTS = Module.instance_method(:constants)
      MODULE_AUTOLOAD_P = Module.instance_method(:autoload?)
      MODULE_CONST_GET = Module.instance_method(:const_get)
      MODULE_CONST_DEFINED = Module.instance_method(:const_defined?)
      KERNEL_CLASS = ::Kernel.instance_method(:class)
      private_constant :CLASS_SUPERCLASS, :MODULE_INCLUDED_MODULES, :MODULE_ANCESTORS,
        :MODULE_CLASS_VARIABLES, :MODULE_CONSTANTS, :MODULE_AUTOLOAD_P, :MODULE_CONST_GET,
        :MODULE_CONST_DEFINED, :KERNEL_CLASS

      # @param logger [Logger] Logger instance (SymbolDatabase::Logger facade or compatible)
      # @param settings [Configuration::Settings] Tracer settings
      def initialize(logger:, settings:)
        @logger = logger
        @settings = settings
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
        return nil unless Module === mod
        mod_name = safe_mod_name(mod)
        return nil unless mod_name

        return nil unless user_code_module?(mod)

        source_file = find_source_file(mod)
        return nil unless source_file

        inner_scope = if Class === mod
          extract_class_scope(mod)
        else
          extract_module_scope(mod)
        end

        wrap_in_file_scope(source_file, [inner_scope])
      rescue => e
        @logger.debug { "symdb: failed to extract #{mod_name || '<unknown>'}: #{e.class}: #{e.message}" }
        nil
      end

      # Extract symbols from all loaded modules and classes.
      # Returns an array of FILE scopes with proper FQN-based nesting.
      #
      # Two-pass algorithm:
      # Pass 1 (`build_per_file_index`): iterate ObjectSpace once, building
      #   `{ file_path => [[mod_name, mod, [method_name_symbol, ...]], ...] }`.
      #   Stores Symbol method names + Module refs only; no UnboundMethod retention
      #   between passes.
      # Pass 2 (`build_file_scope`): for each file in the index, resolve
      #   UnboundMethods just-in-time, build the nested MODULE/CLASS scope tree from
      #   FQN splitting, and produce one FILE Scope. The per-file working set is
      #   released as soon as the FILE scope is yielded (or accumulated into the
      #   returned Array, in legacy mode).
      #
      # This is the production path used by Component. Methods are split by source file,
      # so a class reopened across two files produces two FILE scopes, each with only
      # the methods defined in that file.
      #
      # Memory profile (with a block):
      #   - Pass 1 builds a per-file index containing only Symbol method names plus
      #     Module references. No UnboundMethod objects are retained between passes.
      #   - Pass 2 processes one file at a time. The peak per file is bounded by the
      #     number of methods that live in that one file across all its modules
      #     (typical Rails: tens of methods; pathological case: a single very large
      #     source file). Once a FILE scope is yielded and the caller stops referencing
      #     it, the entire per-file working set becomes garbage.
      #
      # This is O(largest_file + batch_buffer), not O(total_classes).
      #
      # Without a block, returns the full `Array<Scope>` (legacy form, used by specs).
      # The Array itself still scales with the number of files, so block form is the
      # one to use for production memory bounds.
      #
      # @yieldparam scope [Scope] FILE scope for one source file
      # @return [Array<Scope>, nil] Array of FILE scopes when called without a block; nil when a block is given
      def extract_all
        index = build_per_file_index

        if block_given?
          # Drain the index destructively so each per-file entry becomes eligible for
          # collection as soon as its FILE scope is yielded and consumed. Hash#shift
          # returns [key, value] on a non-empty hash and nil when empty, so the
          # `while (pair = ...)` form is the drain. Indexing pair[0]/pair[1] rather
          # than destructuring avoids introducing names into method scope that would
          # then shadow the else-branch's block parameters.
          while (pair = index.shift)
            scope = build_file_scope(pair[0], pair[1])
            yield scope if scope
          end
          nil
        else
          # Legacy non-block form for specs. No memory bound — the full Array is
          # materialized.
          result = []
          index.each do |path, file_entries|
            scope = build_file_scope(path, file_entries)
            result << scope if scope
          end
          result
        end
      rescue => e
        @logger.debug { "symdb: error in extract_all: #{e.class}: #{e.message}" }
        block_given? ? nil : []
      end

      private

      # Safe Module#name lookup — some classes override the singleton `name` method
      # (e.g. Faker::Travel::Airport defines `def name(size:, region:)` in class << self,
      # which shadows Module#name and raises ArgumentError when called without args).
      # @param mod [Module] The module
      # @return [String, nil] Module name or nil
      def safe_mod_name(mod)
        MODULE_NAME.bind(mod).call
      rescue => e
        @logger.debug { "symdb: safe_mod_name failed: #{e.class}: #{e.message}" }
        nil
      end

      # Verify that mod_name still resolves to mod through Ruby's constant
      # table. Returns false when a Class/Module has been detached from its
      # constant (via remove_const) but still carries the cached Module#name —
      # see build_per_file_index for the failure mode this protects.
      #
      # Walks the namespace path segment-by-segment. For each segment:
      # 1. Check for a pending autoload directly on the current namespace.
      #    If present, const_get would trigger it — loading customer code as
      #    a side effect of symbol extraction and raising LoadError if the
      #    target file is missing (LoadError is ScriptError, not StandardError,
      #    and would propagate past the outer rescue in
      #    build_per_file_index). Return false instead.
      # 2. Otherwise, require the constant to be directly defined on this
      #    namespace (const_defined?(sym, false)) and descend via
      #    const_get(sym, false). The direct-only lookup means an ancestor's
      #    pending autoload at the same name does not affect the result: a
      #    subclass with its own binding resolves through the binding, an
      #    inherited autoload triggers nothing.
      #
      # Uses `current.autoload?(sym, false)` (the inherit=false form, added
      # in Ruby 2.7) so the question is strictly "is there an autoload
      # registered directly on this namespace?" and ancestors' pending
      # autoloads at the same name do not affect the result.
      # @param mod_name [String]
      # @param mod [Module]
      # @return [Boolean]
      def resolves_to_same_module?(mod_name, mod)
        current = Object
        mod_name.split('::').each do |seg|
          sym = seg.to_sym
          return false if MODULE_AUTOLOAD_P.bind(current).call(sym, false)
          return false unless MODULE_CONST_DEFINED.bind(current).call(sym, false)
          current = MODULE_CONST_GET.bind(current).call(sym, false)
        end
        current.equal?(mod)
      rescue NameError, ArgumentError, TypeError
        # Expected "no" outcome for stale/detached classes — the whole point
        # of this predicate. Per the rescue convention in this file's header
        # comment: inner per-item rescues are expected failures, no logging.
        false
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
        # Note: bare 'Datadog' must be checked separately — start_with?('Datadog::')
        # doesn't match the root module itself.
        return false if mod_name == 'Datadog' || mod_name.start_with?('Datadog::')

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
      # Module#const_source_location to locate the module via its constants.
      # This handles patterns like `module ApplicationCable; class Channel...; end; end`
      # where the namespace module itself has no methods but defines user-code classes.
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

        # Use const_source_location to find where this class/module is declared.
        # This handles two cases:
        #   1. Classes with no user-defined methods (e.g. AR models with only associations) whose
        #      generated methods point to gem code — we find the `class Foo` declaration instead.
        #   2. Namespace-only modules (`module Foo; class Bar; end; end`) with no methods at all.
        mod_name = safe_mod_name(mod)
        if mod_name
          # Look up the class/module by its last name component in its enclosing namespace.
          parts = mod_name.split('::')
          const_name = parts.last
          namespace = if parts.length > 1
            begin
              MODULE_CONST_GET.bind(Object).call(parts[0..-2].join('::')) # steep:ignore
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
              @logger.debug { "symdb: const_source_location(#{const_name}) failed: #{e.class}: #{e.message}" }
              nil
            end

            if location && !location.empty?
              path = location[0]
              return path if path && !path.empty? && user_code_path?(path)
              fallback ||= ((path && !path.empty?) ? path : nil)
            end
          end

          # Also scan constants defined by mod itself (namespace-only modules).
          MODULE_CONSTANTS.bind(mod).call(false).each do |child_const_name|
            location = begin
              mod.const_source_location(child_const_name)
            rescue => e
              @logger.debug { "symdb: const_source_location(#{child_const_name}) failed: #{e.class}: #{e.message}" }
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
        @logger.debug { "symdb: error finding source file for #{safe_mod_name(mod) || '<unknown>'}: #{e.class}: #{e.message}" }
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

        Scope.new(
          scope_type: 'MODULE',
          name: safe_mod_name(mod),
          source_file: source_file,
          start_line: UNKNOWN_MIN_LINE,
          end_line: UNKNOWN_MAX_LINE,
          symbols: extract_scope_symbols(mod)
        )
      end

      # Extract CLASS scope
      # @param klass [Class] The class
      # @return [Scope] The class scope
      def extract_class_scope(klass)
        methods = klass.instance_methods(false)
        start_line, end_line = calculate_class_line_range(klass, methods)
        source_file = find_source_file(klass)

        Scope.new(
          scope_type: 'CLASS',
          name: safe_mod_name(klass),
          source_file: source_file,
          start_line: start_line,
          end_line: end_line,
          language_specifics: build_class_language_specifics(klass),
          scopes: extract_method_scopes(klass),
          symbols: extract_scope_symbols(klass)
        )
      end

      # Calculate class line range from method locations.
      # Start from the earliest method start, end at the latest method end (derived
      # from iseq trace_points so methods spanning multiple lines aren't truncated).
      # @param klass [Class] The class
      # @param methods [Array<Symbol>] Method names
      # @return [Array<Integer, Integer>] [start_line, end_line]
      def calculate_class_line_range(klass, methods)
        starts = []
        ends = []
        methods.each do |method_name|
          method = klass.instance_method(method_name)
          location = method.source_location
          next unless location && location[0]
          starts << location[1]
          _ranges, method_end = extract_targetable_lines(method, location[1])
          ends << method_end
        end

        return [UNKNOWN_MIN_LINE, UNKNOWN_MAX_LINE] if starts.empty?

        [starts.min, ends.max]
      rescue => e
        @logger.debug { "symdb: error calculating line range for #{safe_mod_name(klass)}: #{e.class}: #{e.message}" }
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
        # Anonymous superclasses (class Foo < Class.new { ... }) have nil name; compact to skip.
        superclass = CLASS_SUPERCLASS.bind(klass).call
        if superclass && !superclass.equal?(Object) && !superclass.equal?(BasicObject)
          super_name = safe_mod_name(superclass)
          specifics[:super_classes] = [super_name] if super_name
        end

        # Included modules (exclude common ones).
        # included_modules returns the entire ancestor chain's mixins, not only directly
        # included ones. This is intentional: the field reports "modules this class
        # responds to," which is what the consumer (UI navigation, probe context) needs.
        included = MODULE_INCLUDED_MODULES.bind(klass).call.map { |m| safe_mod_name(m) }.reject do |name|
          name.nil? || EXCLUDED_COMMON_MODULES.any? { |prefix| name.start_with?(prefix) }
        end
        specifics[:included_modules] = included unless included.empty?

        # Prepended modules
        # Take all ancestors before the class itself (prepending inserts modules before the class in ancestor chain).
        # This code path is taken when a class has prepended modules (e.g., class Foo; prepend Bar; end).
        # Single-pass collection avoids the intermediate arrays from take_while.map.compact.
        # Test coverage: spec/datadog/symbol_database/extractor_spec.rb tests prepend behavior.
        prepended = []
        MODULE_ANCESTORS.bind(klass).call.each do |a|
          break if a.equal?(klass)
          name = safe_mod_name(a)
          prepended << name if name
        end
        specifics[:prepended_modules] = prepended unless prepended.empty?

        specifics
      rescue => e
        @logger.debug { "symdb: error building language specifics for #{safe_mod_name(klass)}: #{e.class}: #{e.message}" }
        {}
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
        @logger.debug { "symdb: failed to extract methods from #{safe_mod_name(klass)}: #{e.class}: #{e.message}" }
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

        targetable_lines, end_line = extract_targetable_lines(method, line)

        Scope.new(
          scope_type: 'METHOD',
          name: method_name.to_s,
          source_file: source_file,
          start_line: line,
          end_line: end_line,
          targetable_lines: targetable_lines,
          language_specifics: {
            visibility: method_visibility(klass, method_name),
            method_type: method_type.to_s,
            arity: method.arity
          },
          symbols: extract_method_parameters(method)
        )
      rescue => e
        @logger.debug { "symdb: failed to extract method #{safe_mod_name(klass)}##{method_name}: #{e.class}: #{e.message}" }
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

      # Extract targetable lines and end_line from a method's bytecode.
      # Returns [ranges, end_line] where ranges is an array of {start:, end:} hashes
      # or nil if iseq is unavailable (C-extension methods).
      # @param method [Method, UnboundMethod] The method
      # @param start_line [Integer] Fallback end_line if iseq unavailable
      # @return [Array(Array<Hash>, Integer), Array(nil, Integer)]
      def extract_targetable_lines(method, start_line)
        iseq = RubyVM::InstructionSequence.of(method) # steep:ignore
        unless iseq
          @logger.debug { "symdb: no iseq for #{method.name} (C extension or native), skipping targetable lines" }
          return [nil, start_line]
        end

        lines = iseq.trace_points
          .select { |_, event| TARGETABLE_LINE_EVENTS.include?(event) }
          .map(&:first)
          .uniq
          .sort

        end_line = lines.max || start_line
        ranges = build_targetable_ranges(lines)
        result = ranges.empty? ? nil : ranges
        @logger.debug { "symdb: #{method.name} targetable lines: #{result ? "#{ranges.size} range(s), lines #{lines.first}..#{lines.last}" : 'none (no matching events)'}" }
        [result, end_line]
      end

      # Compress sorted line numbers into consecutive ranges.
      # [4, 5, 6, 8, 10, 11] => [{start: 4, end: 6}, {start: 8, end: 8}, {start: 10, end: 11}]
      # @param lines [Array<Integer>] Sorted, deduplicated line numbers
      # @return [Array<Hash>] Array of {start:, end:} range hashes
      def build_targetable_ranges(lines)
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
      # @return [Array<Symbol>] Parameter symbols
      def extract_method_parameters(method)
        method_name = begin
          method.name.to_s
        rescue => e
          @logger.debug { "symdb: method.name failed: #{e.class}: #{e.message}" }
          'unknown'
        end
        params = method.parameters

        return [] if params.nil? || params.empty?

        Core::Utils::EnumerableCompat.filter_map(params) do |param_type, param_name|
          # Skip block parameters for MVP
          next if param_type == :block

          # Skip if param_name is nil — normal for generated methods (attr_writer, attr_accessor).
          # See pitfall 37 and specs/json-schema.md "Discovered During Implementation".
          next if param_name.nil?

          Symbol.new(
            symbol_type: 'ARG',
            name: param_name.to_s,
            line: UNKNOWN_MIN_LINE,  # Parameters available in entire method
          )
        end
      rescue => e
        @logger.debug { "symdb: failed to extract parameters from #{method_name}: #{e.class}: #{e.message}" }
        []
      end

      # ── extract_all helpers ──────────────────────────────────────────────

      # Sleep between chunks of modules processed in build_per_file_index so
      # request-handling threads have guaranteed CPU time while extraction is in
      # flight. Unlike Thread.pass (which only offers the GVL among runnable
      # threads and leaves the extractor immediately re-runnable), sleep removes
      # the extractor thread from the runnable set for a fixed duration, capping
      # its CPU share at sleep_work_ratio regardless of GVL scheduling.
      #
      # The cadence is measured in modules that pass the singleton-class fast-path
      # skip — singleton classes are discarded in microseconds and counting them
      # would add wall-clock delay disproportionate to the work being done (e.g.
      # on heavily monkey-patched processes that retain large singleton chains).
      SLEEP_EVERY_N_MODULES = 100
      SLEEP_SECONDS = 0.001
      private_constant :SLEEP_EVERY_N_MODULES, :SLEEP_SECONDS

      # Pass 1 (memory-bounded form): build a per-file index of
      # `{ file_path => [[mod_name, mod, [method_name_symbol, ...]], ...] }`.
      #
      # Stores Symbol method names plus Module references only — no UnboundMethod
      # objects retained between passes. UnboundMethods created here (to read
      # `source_location`) become garbage as the inner loop ends.
      #
      # The Module references are pointer-sized and the modules are already kept
      # alive in ObjectSpace, so adding them to the index costs no extra retention.
      #
      # @return [Hash{String=>Array<Array(String, Module, Array<Symbol>)>}]
      def build_per_file_index
        index = {}
        seen = 0

        ObjectSpace.each_object(Module) do |mod|
          # Singleton classes (per-object metaclasses) are never user-code classes.
          # They're not const-referenced, DI cannot instrument methods on a singular
          # object instance, so skipping them is both correct and cheap.
          next if MODULE_SINGLETON_CLASS_PRED.bind(mod).call

          seen += 1
          sleep SLEEP_SECONDS if (seen % SLEEP_EVERY_N_MODULES).zero?

          mod_name = safe_mod_name(mod)
          next unless mod_name
          next unless resolves_to_same_module?(mod_name, mod)
          next unless user_code_module?(mod)

          file_to_names = collect_method_names_by_file(mod)

          # Namespace-only modules (no own methods) — use find_source_file as the
          # canonical file so the FILE scope still gets a MODULE entry.
          if file_to_names.empty?
            source_file = find_source_file(mod)
            file_to_names[source_file] = [] if source_file
          end

          next if file_to_names.empty?

          file_to_names.each do |file_path, method_names|
            (index[file_path] ||= []) << [mod_name, mod, method_names]
          end
        rescue => e
          @logger.debug { "symdb: error indexing #{mod_name || '<unknown>'}: #{e.class}: #{e.message}" }
        end

        index
      end

      # For a single module, return `{ file_path => [method_name_symbol, ...] }`.
      # Stores only the method-name symbols and their file paths — UnboundMethod
      # objects allocated to read `source_location` are not retained between
      # passes, so they can be GC'd as soon as the inner loop ends.
      def collect_method_names_by_file(mod)
        result = Hash.new { |h, k| h[k] = [] } # steep:ignore

        # Module#instance_methods(false) already returns both public and protected
        # methods, so iterating it plus private_instance_methods covers all three
        # visibilities without an intermediate merged array.
        [mod.instance_methods(false), mod.private_instance_methods(false)].each do |method_names|
          method_names.each do |method_name|
            method = mod.instance_method(method_name)
            loc = method.source_location
            next unless loc
            next unless user_code_path?(loc[0])

            result[loc[0]] << method_name
          rescue => e
            @logger.debug { "symdb: error indexing method #{method_name}: #{e.class}: #{e.message}" }
          end
        end

        result
      rescue => e
        @logger.debug { "symdb: error indexing methods: #{e.class}: #{e.message}" }
        {}
      end

      # Pass 2: build the FILE scope for one source file by walking just the modules
      # that contribute methods to it. Resolves UnboundMethods just-in-time per
      # method; the per-method scratch is collected by GC as each module's loop body
      # ends. The returned Scope is the only thing the caller needs to keep alive
      # — once the caller drops it, the entire per-file working set is collectable.
      #
      # @param file_path [String]
      # @param entries [Array<Array(String, Module, Array<Symbol>)>] tuples produced by build_per_file_index
      # @return [Scope, nil] FILE scope, or nil if nothing extractable
      def build_file_scope(file_path, entries)
        return nil if entries.empty?

        root = {
          name: file_path, type: 'FILE', children: {},
          methods: [], mod: nil, source_file: file_path, fqn: nil,
        }

        # Sort by FQN depth so parent namespaces are placed before children.
        sorted = entries.sort_by { |(mod_name, _, _)| mod_name.count(':') }

        sorted.each do |mod_name, mod, method_names|
          # Resolve UnboundMethods for this (mod, file) just-in-time. These objects
          # live only as long as the tree node holds them; they are released when
          # convert_tree_to_scope finishes building the file's Scope.
          method_infos = Core::Utils::EnumerableCompat.filter_map(method_names) do |name|
            method = mod.instance_method(name)
            # Pass 1 (build_per_file_index) recorded this method under file_path.
            # If the method has been redefined in another file between the two
            # passes (e.g. a class reopened during a Rails reload while extract_all
            # is iterating), the resolved UnboundMethod's source_location now
            # points elsewhere. Drop the stale entry — the hot-load TracePoint
            # enqueues the redefined class and the next debounce window extracts
            # it under the new file_path.
            loc = method.source_location
            next nil unless loc && loc[0] == file_path
            {name: name, method: method, type: :instance}
          rescue => e
            @logger.debug { "symdb: error resolving #{mod_name}##{name}: #{e.class}: #{e.message}" }
            nil
          end

          # If Pass 1 recorded methods for this module but every one of them has
          # moved out of file_path between the passes, drop the entry — otherwise
          # the FILE scope would carry an empty CLASS/MODULE node at a location
          # the module no longer lives in.
          next if method_names.any? && method_infos.empty?

          parts = mod_name.split('::')
          place_in_tree(root, parts, mod, mod_name, method_infos, file_path)
        rescue => e
          @logger.debug { "symdb: error placing #{mod_name} in tree: #{e.class}: #{e.message}" }
        end

        # steep:ignore:start
        # Steep widens root[:children] to the union of all value types declared in
        # the literal (String | Hash | Array | nil), losing the Hash narrowing.
        return nil if root[:children].empty?
        # steep:ignore:end

        convert_tree_to_scope(file_path, root)
      end

      # Place a module/class in the file tree at the correct nesting depth.
      # Creates intermediate namespace nodes as needed.
      # mod_name is the safe name (resolved via Module#instance_method bind) —
      # callers must not pass raw mod.name, since classes that override singleton
      # name (e.g. Faker::Travel::Airport) will raise.
      def place_in_tree(root, name_parts, mod, mod_name, methods, file_path)
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
          leaf[:type] = (Class === mod) ? 'CLASS' : 'MODULE'
          leaf[:mod] = mod
        else
          leaf = {
            name: mod_name,
            type: (Class === mod) ? 'CLASS' : 'MODULE',
            children: {}, methods: [],
            mod: mod, source_file: file_path,
            fqn: mod_name
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
        current = Object
        fqn.split('::').each do |seg|
          sym = seg.to_sym
          pending_autoload = if RubyVersion.is?('>= 2.7')
            MODULE_AUTOLOAD_P.bind(current).call(sym, false)
          else
            MODULE_AUTOLOAD_P.bind(current).call(sym)
          end
          return 'MODULE' if pending_autoload
          return 'MODULE' unless MODULE_CONST_DEFINED.bind(current).call(sym, false)
          current = MODULE_CONST_GET.bind(current).call(sym, false)
        end
        (Class === current) ? 'CLASS' : 'MODULE'
      rescue => e
        @logger.debug { "symdb: resolve_scope_type(#{fqn}) failed: #{e.class}: #{e.message}, defaulting to MODULE" }
        'MODULE'
      end

      # Convert a single file tree (built by build_file_scope) to a FILE Scope.
      # @param file_path [String] Source file path
      # @param root [Hash] Tree node from build_file_scope
      # @return [Scope] FILE scope
      def convert_tree_to_scope(file_path, root)
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
          scopes: root[:children].values.map { |child| convert_node_to_scope(child) },
        )
      end

      # Convert a single hash node to a Scope object (recursive).
      # @param node [Hash] Tree node
      # @return [Scope] Scope object
      def convert_node_to_scope(node)
        # Build method scopes from collected method entries
        method_scopes = Core::Utils::EnumerableCompat.filter_map(node[:methods]) do |method_info|
          build_instance_method_scope(node[:mod], method_info[:name], method_info[:method])
        end

        # Recurse into child scopes (nested modules/classes)
        child_scopes = node[:children].values.map { |child| convert_node_to_scope(child) }

        # Compute line range: start from the earliest method start, end at the latest
        # method end. Using max(start_line) would underreport the class's end_line for
        # classes whose last method spans multiple lines.
        starts = method_scopes.map(&:start_line).reject { |l| l == UNKNOWN_MIN_LINE } # steep:ignore
        ends = method_scopes.map(&:end_line).reject { |l| l == UNKNOWN_MAX_LINE } # steep:ignore
        start_line = starts.empty? ? UNKNOWN_MIN_LINE : starts.min
        end_line = ends.empty? ? UNKNOWN_MAX_LINE : ends.max

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

        targetable_lines, end_line = extract_targetable_lines(method, line)

        Scope.new(
          scope_type: 'METHOD',
          name: method_name.to_s,
          source_file: source_file,
          start_line: line,
          end_line: end_line,
          targetable_lines: targetable_lines,
          language_specifics: {
            visibility: klass ? method_visibility(klass, method_name) : 'public', # steep:ignore
            method_type: 'instance',
            arity: method.arity
          },
          symbols: extract_method_parameters(method)
        )
      rescue => e
        klass_name = klass ? (safe_mod_name(klass) || '<unknown>') : '<unknown>'
        @logger.debug { "symdb: failed to build method scope #{klass_name}##{method_name}: #{e.class}: #{e.message}" }
        nil
      end

      # Extract symbols (constants, class variables) from a module or class.
      # Class variables are emitted only for classes; constants for both.
      # @param mod [Module] The module or class
      # @return [Array<Symbol>] Symbols
      def extract_scope_symbols(mod)
        symbols = []

        # Class variables (only for classes)
        if Class === mod
          MODULE_CLASS_VARIABLES.bind(mod).call(false).each do |var_name|
            symbols << Symbol.new(
              symbol_type: 'STATIC_FIELD',
              name: var_name.to_s,
              line: UNKNOWN_MIN_LINE
            )
          end
        end

        # Constants (excluding nested modules/classes).
        # Skip autoloaded constants to avoid triggering loading as a side effect.
        MODULE_CONSTANTS.bind(mod).call(false).each do |const_name|
          next if MODULE_AUTOLOAD_P.bind(mod).call(const_name)
          const_value = MODULE_CONST_GET.bind(mod).call(const_name)
          next if Module === const_value

          symbols << Symbol.new(
            symbol_type: 'STATIC_FIELD',
            name: const_name.to_s,
            line: UNKNOWN_MIN_LINE,
            type: safe_mod_name(KERNEL_CLASS.bind(const_value).call)
          )
        rescue NameError, LoadError, NoMethodError, TypeError => e # standard:disable Lint/ShadowedException
          # Expected: constant removed/undefined (NameError), autoload failure (LoadError),
          # or a value whose class cannot be read (NoMethodError/TypeError). Skipping one
          # constant here keeps the rest of the module's symbols. Logged separately from
          # unexpected errors so the latter stand out in triage. Lint/ShadowedException
          # disabled: these descend from StandardError, but Ruby's rescue-clause-order
          # semantics ensure the bare rescue below only catches exceptions not matched here.
          @logger.debug { "symdb: skipping module constant #{const_name}: #{e.class}: #{e.message}" }
        rescue => e
          @logger.debug { "symdb: unexpected error reading module constant #{const_name}: #{e.class}: #{e.message}" }
        end

        symbols
      rescue => e
        mod_name = safe_mod_name(mod) || '<unknown>'
        @logger.debug { "symdb: failed to extract symbols from #{mod_name}: #{e.class}: #{e.message}" }
        []
      end
    end
  end
end
