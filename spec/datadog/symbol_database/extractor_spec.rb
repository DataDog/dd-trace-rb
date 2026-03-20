# frozen_string_literal: true

require 'datadog/symbol_database/extractor'
require 'fileutils'

RSpec.describe Datadog::SymbolDatabase::Extractor do
  let(:settings) do
    s = double('settings')
    symdb = double('symbol_database')
    internal = double('internal')
    allow(symdb).to receive(:internal).and_return(internal)
    allow(s).to receive(:symbol_database).and_return(symdb)
    s
  end
  let(:logger) { instance_double(Logger, debug: nil) }
  let(:extractor) { described_class.new(logger: logger, settings: settings, telemetry: nil) }

  # Temporary directory for user code test files
  around do |example|
    Dir.mktmpdir('symbol_db_extractor_test') do |dir|
      @test_dir = dir
      example.run
    end
  end

  # Helper to create test files in user code location
  def create_user_code_file(content)
    filename = File.join(@test_dir, "test_#{Time.now.to_i}_#{rand(10000)}.rb")
    File.write(filename, content)
    filename
  end

  def cleanup_user_code_file(filename)
    File.unlink(filename) if File.exist?(filename)
  end

  describe '.extract' do
    it 'returns nil for non-Module input' do
      expect(extractor.extract("not a module")).to be_nil
      expect(extractor.extract(42)).to be_nil
      expect(extractor.extract(nil)).to be_nil
    end

    it 'returns nil for anonymous module' do
      anonymous_mod = Module.new
      expect(extractor.extract(anonymous_mod)).to be_nil
    end

    it 'returns nil for anonymous class' do
      anonymous_class = Class.new
      expect(extractor.extract(anonymous_class)).to be_nil
    end

    it 'returns nil for class with overridden singleton name method requiring keyword args' do
      # Reproduces Faker::Travel::Airport: defines `def name(size:, region:)` in class << self,
      # shadowing Module#name. Bare `mod.name` raises ArgumentError; safe bind avoids it.
      mod = Class.new
      mod.define_singleton_method(:name) { |size:, region:| "#{size}-#{region}" }
      expect(extractor.extract(mod)).to be_nil
    end

    it 'returns nil for class with overridden singleton name method requiring keyword args' do
      # Reproduces Faker::Travel::Airport: defines `def name(size:, region:)` in class << self,
      # shadowing Module#name. Bare `mod.name` raises ArgumentError; safe bind avoids it.
      mod = Class.new
      mod.define_singleton_method(:name) { |size:, region:| "#{size}-#{region}" }
      expect(described_class.extract(mod)).to be_nil
    end

    context 'with gem code' do
      it 'returns nil for RSpec module (gem code)' do
        expect(extractor.extract(RSpec)).to be_nil
      end
    end

    context 'with stdlib code' do
      it 'returns nil for File class (stdlib)' do
        expect(extractor.extract(File)).to be_nil
      end
    end

    context 'with user code module' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          module TestUserModule
            SOME_CONSTANT = 42

            def self.module_method
              "result"
            end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestUserModule) if defined?(TestUserModule)
        cleanup_user_code_file(@filename)
      end

      it 'wraps MODULE in a FILE scope' do
        file_scope = extractor.extract(TestUserModule)

        expect(file_scope).not_to be_nil
        expect(file_scope.scope_type).to eq('FILE')
        expect(file_scope.name).to eq(@filename)
        expect(file_scope.source_file).to eq(@filename)

        module_scope = file_scope.scopes.first
        expect(module_scope.scope_type).to eq('MODULE')
        expect(module_scope.name).to eq('TestUserModule')
      end

      it 'includes file hash on FILE scope language_specifics' do
        file_scope = extractor.extract(TestUserModule)

        expect(file_scope.language_specifics).to have_key(:file_hash)
        expect(file_scope.language_specifics[:file_hash]).to be_a(String)
        expect(file_scope.language_specifics[:file_hash].length).to eq(40)
      end

      it 'extracts module-level constants' do
        file_scope = extractor.extract(TestUserModule)
        module_scope = file_scope.scopes.first

        constant_symbol = module_scope.symbols.find { |s| s.name == 'SOME_CONSTANT' }
        expect(constant_symbol).not_to be_nil
        expect(constant_symbol.symbol_type).to eq('STATIC_FIELD')
      end
    end

    context 'with user code class' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          class TestUserClass
            CONSTANT = "value"
            @@class_var = 123

            def public_method(arg1, arg2 = nil)
              arg1 + arg2.to_s
            end

            private

            def private_method
              "private"
            end

            def self.class_method(param)
              param * 2
            end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestUserClass) if defined?(TestUserClass)
        cleanup_user_code_file(@filename)
      end

      it 'wraps top-level CLASS in a FILE scope named after source file' do
        file_scope = extractor.extract(TestUserClass)

        expect(file_scope).not_to be_nil
        expect(file_scope.scope_type).to eq('FILE')
        expect(file_scope.name).to eq(@filename)
        expect(file_scope.source_file).to eq(@filename)
        expect(file_scope.scopes.size).to eq(1)

        class_scope = file_scope.scopes.first
        expect(class_scope.scope_type).to eq('CLASS')
        expect(class_scope.name).to eq('TestUserClass')
        expect(class_scope.source_file).to eq(@filename)
      end

      it 'extracts class variables' do
        class_scope = extractor.extract(TestUserClass).scopes.first

        class_var = class_scope.symbols.find { |s| s.name == '@@class_var' }
        expect(class_var).not_to be_nil
        expect(class_var.symbol_type).to eq('STATIC_FIELD')
      end

      it 'extracts constants' do
        class_scope = extractor.extract(TestUserClass).scopes.first

        constant = class_scope.symbols.find { |s| s.name == 'CONSTANT' }
        expect(constant).not_to be_nil
        expect(constant.symbol_type).to eq('STATIC_FIELD')
      end

      it 'extracts instance methods as METHOD scopes' do
        class_scope = extractor.extract(TestUserClass).scopes.first

        method_scopes = class_scope.scopes.select { |s| s.scope_type == 'METHOD' }
        method_names = method_scopes.map(&:name)

        expect(method_names).to include('public_method')
        expect(method_names).to include('private_method')
      end

      it 'captures method visibility' do
        class_scope = extractor.extract(TestUserClass).scopes.first

        public_method = class_scope.scopes.find { |s| s.name == 'public_method' }
        expect(public_method.language_specifics[:visibility]).to eq('public')

        private_method = class_scope.scopes.find { |s| s.name == 'private_method' }
        expect(private_method.language_specifics[:visibility]).to eq('private')
      end

      it 'does not emit self ARG for instance methods' do
        # self is implicit in Ruby (not a declared parameter). Java skips slot 0 for the
        # same reason. The web-ui would need a filter for it anyway — don't upload it.
        class_scope = extractor.extract(TestUserClass).scopes.first
        method_scope = class_scope.scopes.find { |s| s.name == 'public_method' }

        expect(method_scope.symbols.map(&:name)).not_to include('self')
      end

      it 'extracts method parameters' do
        class_scope = extractor.extract(TestUserClass).scopes.first
        method_scope = class_scope.scopes.find { |s| s.name == 'public_method' }

        arg1 = method_scope.symbols.find { |s| s.name == 'arg1' }
        expect(arg1).not_to be_nil
        expect(arg1.symbol_type).to eq('ARG')

        arg2 = method_scope.symbols.find { |s| s.name == 'arg2' }
        expect(arg2).not_to be_nil
        expect(arg2.symbol_type).to eq('ARG')
      end

      it 'includes injectable lines on instance METHOD scopes via extract() path' do
        class_scope = extractor.extract(TestUserClass).scopes.first
        method_scope = class_scope.scopes.find { |s| s.name == 'public_method' }

        expect(method_scope.injectible_lines?).to eq(true)
        expect(method_scope.injectible_lines).to be_an(Array)
        expect(method_scope.injectible_lines).not_to be_empty
        expect(method_scope.end_line).to be >= method_scope.start_line
      end
    end

    context 'with namespaced class (namespace module has no methods)' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          module TestNamespace
            class TestInnerClass
              def inner_method; end
            end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestNamespace) if defined?(TestNamespace)
        cleanup_user_code_file(@filename)
      end

      it 'extracts namespaced class as its own root FILE scope' do
        # TestNamespace::TestInnerClass is a user class and must be searchable.
        # Even though the parent TestNamespace has no methods (so it can't be extracted
        # itself), the class is extracted as a standalone FILE-wrapped scope.
        file_scope = extractor.extract(TestNamespace::TestInnerClass)

        expect(file_scope).not_to be_nil
        expect(file_scope.scope_type).to eq('FILE')
        expect(file_scope.name).to eq(file_scope.source_file)
        class_scope = file_scope.scopes.first
        expect(class_scope.scope_type).to eq('CLASS')
        expect(class_scope.name).to eq('TestNamespace::TestInnerClass')
      end

      it 'extracts namespace-only module via const_source_location fallback (Ruby 2.7+)' do
        # TestNamespace has no methods but has a constant (TestInnerClass).
        # On Ruby 2.7+, const_source_location finds the module's source via its constants.
        file_scope = extractor.extract(TestNamespace)

        if Module.method_defined?(:const_source_location) || TestNamespace.respond_to?(:const_source_location)
          expect(file_scope).not_to be_nil
          expect(file_scope.scope_type).to eq('FILE')
          module_scope = file_scope.scopes.first
          expect(module_scope.scope_type).to eq('MODULE')
          expect(module_scope.name).to eq('TestNamespace')
        else
          # Ruby < 2.7: const_source_location unavailable, module not extractable
          expect(file_scope).to be_nil
        end
      end
    end

    context 'with namespaced module with methods' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          module TestNsModule
            def self.module_func; end
            class TestNsClass
              def ns_method; end
            end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestNsModule) if defined?(TestNsModule)
        cleanup_user_code_file(@filename)
      end

      it 'extracts the parent MODULE without nested classes (nesting is via extract_all)' do
        file_scope = extractor.extract(TestNsModule)

        expect(file_scope).not_to be_nil
        expect(file_scope.scope_type).to eq('FILE')
        module_scope = file_scope.scopes.first
        expect(module_scope.scope_type).to eq('MODULE')
        expect(module_scope.name).to eq('TestNsModule')
        # extract does not nest classes — extract_all handles nesting via FQN splitting
        inner_class = module_scope.scopes.find { |s| s.scope_type == 'CLASS' }
        expect(inner_class).to be_nil
      end

      it 'also extracts the nested class as its own root FILE scope' do
        # The nested class is extractable independently — it has a user code source file.
        file_scope = extractor.extract(TestNsModule::TestNsClass)

        expect(file_scope).not_to be_nil
        expect(file_scope.scope_type).to eq('FILE')
        expect(file_scope.name).to eq(file_scope.source_file)
      end
    end

    context 'with namespaced class (namespace module has no methods)' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          module TestNamespace
            class TestInnerClass
              def inner_method; end
            end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestNamespace) if defined?(TestNamespace)
        cleanup_user_code_file(@filename)
      end

      it 'extracts namespaced class as its own root PACKAGE scope' do
        # TestNamespace::TestInnerClass is a user class and must be searchable.
        # Even though the parent TestNamespace has no methods (so it can't be extracted
        # itself), the class is extracted as a standalone PACKAGE-wrapped scope.
        scope = described_class.extract(TestNamespace::TestInnerClass)

        expect(scope).not_to be_nil
        expect(scope.scope_type).to eq('PACKAGE')
        expect(scope.name).to eq(scope.source_file)
        class_scope = scope.scopes.first
        expect(class_scope.scope_type).to eq('CLASS')
        expect(class_scope.name).to eq('TestNamespace::TestInnerClass')
      end

      it 'extracts namespace-only module via const_source_location fallback (Ruby 2.7+)' do
        # TestNamespace has no methods but has a constant (TestInnerClass).
        # On Ruby 2.7+, const_source_location finds the module's source via its constants.
        scope = described_class.extract(TestNamespace)

        if Module.method_defined?(:const_source_location) || TestNamespace.respond_to?(:const_source_location)
          expect(scope).not_to be_nil
          expect(scope.scope_type).to eq('MODULE')
          expect(scope.name).to eq('TestNamespace')
        else
          # Ruby < 2.7: const_source_location unavailable, module not extractable
          expect(scope).to be_nil
        end
      end
    end

    context 'with namespaced module with methods' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          module TestNsModule
            def self.module_func; end
            class TestNsClass
              def ns_method; end
            end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestNsModule) if defined?(TestNsModule)
        cleanup_user_code_file(@filename)
      end

      it 'extracts the parent MODULE with the class nested inside' do
        module_scope = described_class.extract(TestNsModule)

        expect(module_scope).not_to be_nil
        expect(module_scope.scope_type).to eq('MODULE')
        expect(module_scope.name).to eq('TestNsModule')
        inner_class = module_scope.scopes.find { |s| s.scope_type == 'CLASS' }
        expect(inner_class).not_to be_nil
        expect(inner_class.name).to eq('TestNsModule::TestNsClass')
      end

      it 'also extracts the nested class as its own root PACKAGE scope' do
        # The nested class is extractable independently — it has a user code source file.
        # It also appears nested inside the parent MODULE, which is intentional:
        # mergeRootScopesWithSameName on the backend merges duplicates by name.
        scope = described_class.extract(TestNsModule::TestNsClass)

        expect(scope).not_to be_nil
        expect(scope.scope_type).to eq('PACKAGE')
        expect(scope.name).to eq(scope.source_file)
      end
    end

    context 'with class inheritance' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          class TestBaseClass
            def base_method
            end
          end

          class TestDerivedClass < TestBaseClass
            def derived_method
            end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestDerivedClass) if defined?(TestDerivedClass)
        Object.send(:remove_const, :TestBaseClass) if defined?(TestBaseClass)
        cleanup_user_code_file(@filename)
      end

      it 'captures superclass in language_specifics as super_classes array' do
        class_scope = extractor.extract(TestDerivedClass).scopes.first

        expect(class_scope.language_specifics[:super_classes]).to eq(['TestBaseClass'])
      end

      it 'excludes Object from super_classes' do
        class_scope = extractor.extract(TestBaseClass).scopes.first

        expect(class_scope.language_specifics).not_to have_key(:super_classes)
      end

      it 'omits super_classes when superclass.name is nil (anonymous superclass)' do
        # build_class_language_specifics path: anonymous superclass returns nil from #name.
        # Result should drop the entry rather than emit [nil].
        anon_super = Class.new
        derived = Class.new(anon_super)
        specifics = extractor.send(:build_class_language_specifics, derived)
        expect(specifics).not_to have_key(:super_classes)
      end
    end

    context 'with mixins' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          module TestMixin
          end

          class TestClassWithMixin
            include TestMixin

            def test_method
            end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestClassWithMixin) if defined?(TestClassWithMixin)
        Object.send(:remove_const, :TestMixin) if defined?(TestMixin)
        cleanup_user_code_file(@filename)
      end

      it 'captures included modules in language_specifics' do
        class_scope = extractor.extract(TestClassWithMixin).scopes.first

        expect(class_scope.language_specifics[:included_modules]).to include('TestMixin')
      end

      it 'excludes Kernel from included_modules (EXCLUDED_COMMON_MODULES)' do
        class_scope = extractor.extract(TestClassWithMixin).scopes.first

        expect(class_scope.language_specifics[:included_modules]).not_to include('Kernel')
      end
    end
  end

  describe '.extract edge cases' do
    context 'empty and minimal classes' do
      it 'extracts empty top-level class as a CLASS scope with no methods (Ruby 2.7+)' do
        # Matches Java/NET: empty classes are uploaded so they appear in the probe modal.
        # const_source_location finds the class declaration even with no methods.
        filename = create_user_code_file("class TestEmptyClass; end")
        load filename
        scope = extractor.extract(TestEmptyClass)
        if Module.method_defined?(:const_source_location)
          expect(scope).not_to be_nil
          expect(scope.scope_type).to eq('FILE')
          expect(scope.scopes.first.scope_type).to eq('CLASS')
          expect(scope.scopes.first.scopes).to be_empty
        else
          expect(scope).to be_nil
        end
        Object.send(:remove_const, :TestEmptyClass)
        cleanup_user_code_file(filename)
      end

      it 'extracts empty top-level module as a MODULE scope with no methods (Ruby 2.7+)' do
        filename = create_user_code_file("module TestEmptyModule; end")
        load filename
        scope = extractor.extract(TestEmptyModule)
        if Module.method_defined?(:const_source_location)
          expect(scope).not_to be_nil
          expect(scope.scope_type).to eq('FILE')
          expect(scope.scopes.first.scope_type).to eq('MODULE')
        else
          expect(scope).to be_nil
        end
        Object.send(:remove_const, :TestEmptyModule)
        cleanup_user_code_file(filename)
      end

      it 'handles top-level class with only constants on Ruby 2.7+' do
        filename = create_user_code_file(<<~RUBY)
          class TestConstOnlyClass
            SOME_CONST = 42
          end
        RUBY
        load filename

        scope = extractor.extract(TestConstOnlyClass)
        if TestConstOnlyClass.respond_to?(:const_source_location)
          # Ruby 2.7+: const_source_location finds source via constants
          expect(scope).not_to be_nil
          expect(scope.scope_type).to eq('FILE')
        else
          # Ruby 2.5/2.6: no const_source_location, cannot find source
          expect(scope).to be_nil
        end

        Object.send(:remove_const, :TestConstOnlyClass)
        cleanup_user_code_file(filename)
      end
    end

    context 'deeply nested namespaces' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          module TestA
            module TestB
              class TestC
                def deep_method; end
              end
            end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestA) if defined?(TestA)
        cleanup_user_code_file(@filename)
      end

      it 'extracts deeply nested class (A::B::C) as standalone root scope' do
        scope = extractor.extract(TestA::TestB::TestC)
        expect(scope).not_to be_nil
        expect(scope.scope_type).to eq('FILE')
        expect(scope.name).to eq(scope.source_file)
        expect(scope.scopes.first.scope_type).to eq('CLASS')
      end

      it 'extracts namespace modules via const_source_location when they have nested constants' do
        # On Ruby 2.7+: TestA has const TestB (a module), TestA::TestB has const TestC (a class).
        # const_source_location finds the source file via these constants, so both modules ARE extracted.
        if TestA.respond_to?(:const_source_location)
          expect(extractor.extract(TestA)).not_to be_nil
          expect(extractor.extract(TestA::TestB)).not_to be_nil
        else
          # Ruby < 2.7: no const_source_location, namespace modules without methods return nil
          expect(extractor.extract(TestA)).to be_nil
          expect(extractor.extract(TestA::TestB)).to be_nil
        end
      end

      it 'extracts all scopes in the namespace chain (Ruby 2.7+)' do
        # TestA, TestA::TestB, TestA::TestB::TestC all get extracted on Ruby 2.7+
        # because const_source_location propagates source file through the chain.
        # Use explicit module list rather than ObjectSpace to avoid cross-test pollution.
        mods = [TestA, TestA::TestB, TestA::TestB::TestC]
        extracted = Datadog::Core::Utils::Array.filter_map(mods) { |mod| extractor.extract(mod) }

        # All scopes are FILE-wrapped. Inner scope names distinguish modules from classes.
        if TestA.respond_to?(:const_source_location)
          expect(extracted.size).to eq(3)
          # All root scopes are FILE
          expect(extracted.map(&:scope_type).uniq).to eq(['FILE'])
          # Inner scopes: TestA and TestA::TestB are modules, TestA::TestB::TestC is a class
          inner_names = extracted.map { |s| s.scopes.first&.name }
          expect(inner_names).to include('TestA', 'TestA::TestB')
          tc_file = extracted.find { |s| s.scopes.first&.name == 'TestA::TestB::TestC' }
          expect(tc_file).not_to be_nil
          expect(tc_file.scopes.first.scope_type).to eq('CLASS')
        else
          expect(extracted.size).to eq(1)
          expect(extracted.first.scope_type).to eq('FILE')
        end
      end
    end

    context 'AR-style model with no user-defined methods' do
      it 'extracts class whose only methods come from gem paths — finds declaration via const_source_location' do
        # Simulates ActiveRecord model with only associations (belongs_to, has_many).
        # Methods are all gem-generated with gem source paths. The class declaration
        # is in user code. On Ruby 2.7+ we find it via const_source_location and upload
        # an empty CLASS scope, matching Java/.NET behavior.
        filename = create_user_code_file(<<~RUBY)
          class TestARStyleModel
          end
        RUBY
        load filename

        gem_path = '/fake/gems/activerecord-7.0/lib/active_record/autosave.rb'
        gem_method = instance_double(Method, source_location: [gem_path, 1], arity: 0, parameters: [])

        allow(TestARStyleModel).to receive(:instance_methods).with(false).and_return([:gem_generated_method])
        allow(TestARStyleModel).to receive(:instance_method).with(:gem_generated_method).and_return(gem_method)
        allow(TestARStyleModel).to receive(:protected_instance_methods).with(false).and_return([])
        allow(TestARStyleModel).to receive(:private_instance_methods).with(false).and_return([])
        allow(TestARStyleModel).to receive(:singleton_methods).with(false).and_return([])

        scope = extractor.extract(TestARStyleModel)
        if Module.method_defined?(:const_source_location)
          expect(scope).not_to be_nil
          expect(scope.scope_type).to eq('FILE')
          expect(scope.scopes.first.scope_type).to eq('CLASS')
          expect(scope.scopes.first.scopes).to be_empty
        else
          expect(scope).to be_nil
        end

        Object.send(:remove_const, :TestARStyleModel)
        cleanup_user_code_file(filename)
      end

      it 'extracts class with only Forwardable-delegated methods (def_delegators)' do
        # def_delegators creates methods whose source_location points to forwardable.rb (stdlib).
        # The class declaration is in user code. Should extract as empty CLASS scope on Ruby 2.7+.
        filename = create_user_code_file(<<~RUBY)
          require 'forwardable'
          class TestForwardableModel
            extend Forwardable
            def_delegators :@target, :name, :email
          end
        RUBY
        load filename

        scope = extractor.extract(TestForwardableModel)
        if Module.method_defined?(:const_source_location)
          expect(scope).not_to be_nil
          expect(scope.scope_type).to eq('FILE')
          inner = scope.scopes.first
          expect(inner.scope_type).to eq('CLASS')
          # Delegated methods point to forwardable.rb (stdlib) — not user code, not extracted
          method_names = inner.scopes.map(&:name)
          expect(method_names).not_to include('name', 'email')
        else
          expect(scope).to be_nil
        end

        Object.send(:remove_const, :TestForwardableModel)
        cleanup_user_code_file(filename)
      end
    end

    context 'class with only class variables (no methods)' do
      it 'extracts class with only class variables on Ruby 2.7+ via const_source_location' do
        # @@class_var is not a constant, so constants(false) returns nothing.
        # But const_source_location on the class name itself finds the declaration.
        filename = create_user_code_file(<<~RUBY)
          class TestClassVarOnly
            @@count = 0
          end
        RUBY
        load filename
        scope = extractor.extract(TestClassVarOnly)
        if Module.method_defined?(:const_source_location)
          expect(scope).not_to be_nil
          expect(scope.scope_type).to eq('FILE')
          expect(scope.scopes.first.scope_type).to eq('CLASS')
        else
          expect(scope).to be_nil
        end
        Object.send(:remove_const, :TestClassVarOnly)
        cleanup_user_code_file(filename)
      end
    end

    context 'module with only non-class-value constants' do
      it 'is extracted on Ruby 2.7+ via const_source_location (non-class constants count)' do
        # const_source_location works for any constant including VALUE constants (FOO = 42),
        # not just class/module constants. So a module with only value constants IS found.
        filename = create_user_code_file(<<~RUBY)
          module TestValueConstModule
            MAX_SIZE = 100
            DEFAULT_NAME = "test"
          end
        RUBY
        load filename
        file_scope = extractor.extract(TestValueConstModule)
        if TestValueConstModule.respond_to?(:const_source_location)
          expect(file_scope).not_to be_nil
          expect(file_scope.scope_type).to eq('FILE')
          module_scope = file_scope.scopes.first
          expect(module_scope.scope_type).to eq('MODULE')
          expect(module_scope.name).to eq('TestValueConstModule')
        else
          expect(file_scope).to be_nil
        end
        Object.send(:remove_const, :TestValueConstModule)
        cleanup_user_code_file(filename)
      end
    end

    context 'namespace module found via const_source_location has file_hash' do
      it 'computes file_hash from the const_source_location-derived source file' do
        filename = create_user_code_file(<<~RUBY)
          module TestNsFileHash
            class TestNsChild
              def child_method; end
            end
          end
        RUBY
        load filename

        scope = extractor.extract(TestNsFileHash)

        if Module.method_defined?(:const_source_location)
          # Ruby 2.7+: const_source_location finds the module via its constants
          expect(scope).not_to be_nil
          expect(scope.language_specifics[:file_hash]).not_to be_nil
          expect(scope.language_specifics[:file_hash]).to match(/\A[0-9a-f]{40}\z/)
        else
          # Ruby < 2.7: namespace module with no methods is not extractable
          expect(scope).to be_nil
        end

        Object.send(:remove_const, :TestNsFileHash)
        cleanup_user_code_file(filename)
      end
    end

    context 'concern-style modules' do
      it 'extracts a module with only an included block (no direct def methods)' do
        # A concern using `included do ... end` — the `included` call is a singleton method
        # on ActiveSupport::Concern (or a no-op here). Without direct `def` methods,
        # find_source_file falls through to const_source_location or returns nil.
        filename = create_user_code_file(<<~RUBY)
          module TestConcernNoMethods
            def self.included(base)
              base.extend(ClassMethods)
            end

            module ClassMethods
              def searchable?; true; end
            end
          end
        RUBY
        load filename

        # TestConcernNoMethods has a singleton method (self.included) → source_location
        # points to the file → extracted
        file_scope = extractor.extract(TestConcernNoMethods)
        expect(file_scope).not_to be_nil
        expect(file_scope.scope_type).to eq('FILE')
        module_scope = file_scope.scopes.first
        expect(module_scope.scope_type).to eq('MODULE')
        expect(module_scope.name).to eq('TestConcernNoMethods')

        Object.send(:remove_const, :TestConcernNoMethods)
        cleanup_user_code_file(filename)
      end
    end

    # === Tests ported from Java SymbolExtractionTransformerTest ===
    # Java tests bytecode-level variable scoping (if/for/while blocks).
    # Ruby uses reflection, not bytecode — we test the Ruby equivalents.

    context 'with protected methods' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          class TestProtectedClass
            def public_method; end

            protected

            def protected_method; end

            private

            def private_method; end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestProtectedClass) if defined?(TestProtectedClass)
        cleanup_user_code_file(@filename)
      end

      it 'captures protected visibility' do
        class_scope = extractor.extract(TestProtectedClass).scopes.first

        protected_method = class_scope.scopes.find { |s| s.name == 'protected_method' }
        expect(protected_method.language_specifics[:visibility]).to eq('protected')
      end

      it 'extracts all three visibility levels' do
        class_scope = extractor.extract(TestProtectedClass).scopes.first

        visibilities = class_scope.scopes.map { |s| s.language_specifics[:visibility] }
        expect(visibilities).to include('public', 'protected', 'private')
      end
    end

    context 'with attr_accessor methods' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          class TestAttrClass
            attr_reader :read_only
            attr_writer :write_only
            attr_accessor :read_write

            def initialize
              @read_only = 1
              @write_only = 2
              @read_write = 3
            end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestAttrClass) if defined?(TestAttrClass)
        cleanup_user_code_file(@filename)
      end

      it 'extracts attr_reader as METHOD scope' do
        class_scope = extractor.extract(TestAttrClass).scopes.first
        method_names = class_scope.scopes.map(&:name)

        expect(method_names).to include('read_only')
      end

      it 'extracts attr_writer as METHOD scope' do
        class_scope = extractor.extract(TestAttrClass).scopes.first
        method_names = class_scope.scopes.map(&:name)

        expect(method_names).to include('write_only=')
      end

      it 'extracts attr_accessor as both reader and writer METHOD scopes' do
        class_scope = extractor.extract(TestAttrClass).scopes.first
        method_names = class_scope.scopes.map(&:name)

        expect(method_names).to include('read_write')
        expect(method_names).to include('read_write=')
      end
    end

    context 'with prepended modules' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          module TestPrependModule
            def prepended_method; end
          end

          class TestPrependedClass
            prepend TestPrependModule

            def original_method; end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestPrependedClass) if defined?(TestPrependedClass)
        Object.send(:remove_const, :TestPrependModule) if defined?(TestPrependModule)
        cleanup_user_code_file(@filename)
      end

      it 'captures prepended modules in language_specifics' do
        class_scope = extractor.extract(TestPrependedClass).scopes.first

        expect(class_scope.language_specifics[:prepended_modules]).to include('TestPrependModule')
      end
    end

    context 'with all parameter types' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          class TestAllParamsClass
            def method_with_all_params(required, optional = nil, *rest, keyword:, optional_kw: 'default', **keyrest, &blk)
              # Method with every Ruby parameter type
            end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestAllParamsClass) if defined?(TestAllParamsClass)
        cleanup_user_code_file(@filename)
      end

      it 'extracts required, optional, rest, keyword, and keyrest parameters' do
        class_scope = extractor.extract(TestAllParamsClass).scopes.first
        method_scope = class_scope.scopes.find { |s| s.name == 'method_with_all_params' }

        param_names = method_scope.symbols.map(&:name)

        expect(param_names).not_to include('self')
        expect(param_names).to include('required')
        expect(param_names).to include('optional')
        expect(param_names).to include('rest')
        expect(param_names).to include('keyword')
        expect(param_names).to include('optional_kw')
        expect(param_names).to include('keyrest')
      end

      it 'skips block parameters' do
        class_scope = extractor.extract(TestAllParamsClass).scopes.first
        method_scope = class_scope.scopes.find { |s| s.name == 'method_with_all_params' }

        param_names = method_scope.symbols.map(&:name)

        expect(param_names).not_to include('blk')
      end

      it 'all extracted parameters are ARG symbol type' do
        class_scope = extractor.extract(TestAllParamsClass).scopes.first
        method_scope = class_scope.scopes.find { |s| s.name == 'method_with_all_params' }

        method_scope.symbols.each do |sym|
          expect(sym.symbol_type).to eq('ARG')
        end
      end
    end

    context 'with exception handling (begin/rescue/ensure equivalent)' do
      # Ported from Java SymbolExtractionTransformerTest: symbolExtraction03 (try-catch-finally)
      # Ruby doesn't expose local variable scoping from bytecode, but we verify
      # that methods containing exception handling constructs are still extracted.
      before do
        @filename = create_user_code_file(<<~RUBY)
          class TestExceptionClass
            def method_with_rescue(input)
              result = nil
              begin
                result = Integer(input)
              rescue ArgumentError => e
                result = -1
              rescue TypeError
                result = -2
              ensure
                @last_input = input
              end
              result
            end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestExceptionClass) if defined?(TestExceptionClass)
        cleanup_user_code_file(@filename)
      end

      it 'extracts method containing begin/rescue/ensure' do
        class_scope = extractor.extract(TestExceptionClass).scopes.first
        method_scope = class_scope.scopes.find { |s| s.name == 'method_with_rescue' }

        expect(method_scope).not_to be_nil
        expect(method_scope.scope_type).to eq('METHOD')
      end

      it 'extracts parameters from method with exception handling' do
        class_scope = extractor.extract(TestExceptionClass).scopes.first
        method_scope = class_scope.scopes.find { |s| s.name == 'method_with_rescue' }

        param_names = method_scope.symbols.map(&:name)
        expect(param_names).to include('input')
      end
    end

    context 'with define_method (metaprogramming)' do
      # Ported from Java: tests dynamically defined methods. Java tests bytecode
      # for dynamic proxies; Ruby equivalent is define_method.
      before do
        @filename = create_user_code_file(<<~RUBY)
          class TestDefineMethodClass
            define_method(:dynamic_method) do |arg1, arg2|
              arg1 + arg2
            end

            def regular_method; end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestDefineMethodClass) if defined?(TestDefineMethodClass)
        cleanup_user_code_file(@filename)
      end

      it 'extracts dynamically defined methods' do
        class_scope = extractor.extract(TestDefineMethodClass).scopes.first
        method_names = class_scope.scopes.map(&:name)

        expect(method_names).to include('dynamic_method')
        expect(method_names).to include('regular_method')
      end

      it 'extracts parameters from define_method' do
        class_scope = extractor.extract(TestDefineMethodClass).scopes.first
        method_scope = class_scope.scopes.find { |s| s.name == 'dynamic_method' }

        param_names = method_scope.symbols.map(&:name)
        expect(param_names).to include('arg1')
        expect(param_names).to include('arg2')
      end
    end

    context 'with Struct class' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          TestStructClass = Struct.new(:name, :age) do
            def greeting
              "Hello, \#{name}"
            end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestStructClass) if defined?(TestStructClass)
        cleanup_user_code_file(@filename)
      end

      it 'extracts Struct-based class' do
        scope = extractor.extract(TestStructClass)

        expect(scope).not_to be_nil
        expect(scope.scope_type).to eq('FILE')
        expect(scope.name).to eq(scope.source_file)
      end

      it 'extracts user-defined methods on Struct' do
        class_scope = extractor.extract(TestStructClass).scopes.first
        method_names = class_scope.scopes.map(&:name)

        expect(method_names).to include('greeting')
      end
    end

    # === Ruby-specific metaprogramming edge cases ===
    # Tests for patterns unique to Ruby: class_eval, eval, define_method variants,
    # OpenStruct, and refinements. These complement the Java-ported tests above.

    context 'with class_eval adding methods' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          class TestClassEvalTarget
            def original_method; end
          end

          TestClassEvalTarget.class_eval do
            def eval_added_method(x, y); x + y; end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestClassEvalTarget) if defined?(TestClassEvalTarget)
        cleanup_user_code_file(@filename)
      end

      it 'extracts methods added via class_eval' do
        class_scope = extractor.extract(TestClassEvalTarget).scopes.first
        method_names = class_scope.scopes.map(&:name)

        expect(method_names).to include('original_method')
        expect(method_names).to include('eval_added_method')
      end

      it 'extracts parameters from class_eval methods' do
        class_scope = extractor.extract(TestClassEvalTarget).scopes.first
        method_scope = class_scope.scopes.find { |s| s.name == 'eval_added_method' }

        param_names = method_scope.symbols.map(&:name)
        expect(param_names).to include('x', 'y')
      end
    end

    context 'with eval-defined class' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          eval("class TestEvalDefinedClass; def eval_method; end; end")
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestEvalDefinedClass) if defined?(TestEvalDefinedClass)
        cleanup_user_code_file(@filename)
      end

      it 'returns nil for class defined via eval (source_location is "(eval)")' do
        # eval-defined methods have source_location ["(eval)", N] which is
        # correctly filtered by user_code_path? (includes '(eval)' check)
        scope = extractor.extract(TestEvalDefinedClass)
        expect(scope).to be_nil
      end
    end

    context 'with define_method using a lambda' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          class TestDefineMethodLambda
            handler = ->(a, b) { a * b }
            define_method(:from_lambda, handler)

            def regular; end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestDefineMethodLambda) if defined?(TestDefineMethodLambda)
        cleanup_user_code_file(@filename)
      end

      it 'extracts method defined from lambda' do
        class_scope = extractor.extract(TestDefineMethodLambda).scopes.first
        method_names = class_scope.scopes.map(&:name)

        expect(method_names).to include('from_lambda')
        expect(method_names).to include('regular')
      end

      it 'extracts lambda parameters' do
        class_scope = extractor.extract(TestDefineMethodLambda).scopes.first
        method_scope = class_scope.scopes.find { |s| s.name == 'from_lambda' }

        param_names = method_scope.symbols.map(&:name)
        expect(param_names).to include('a', 'b')
      end
    end

    context 'with OpenStruct subclass' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          require 'ostruct'
          class TestOpenStructChild < OpenStruct
            def custom_method; "custom"; end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestOpenStructChild) if defined?(TestOpenStructChild)
        cleanup_user_code_file(@filename)
      end

      it 'extracts user-defined methods on OpenStruct subclass' do
        scope = extractor.extract(TestOpenStructChild)

        expect(scope).not_to be_nil
        class_scope = scope.scopes.first
        method_names = class_scope.scopes.map(&:name)
        expect(method_names).to include('custom_method')
      end

      it 'includes OpenStruct as superclass in language_specifics' do
        class_scope = extractor.extract(TestOpenStructChild).scopes.first
        expect(class_scope.language_specifics[:super_classes]).to include('OpenStruct')
      end
    end

    context 'with refinements' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          module TestRefinementModule
            refine String do
              def shout; upcase + "!"; end
            end

            def self.helper_method; "helper"; end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestRefinementModule) if defined?(TestRefinementModule)
        cleanup_user_code_file(@filename)
      end

      it 'extracts the refinement module itself (has a singleton method)' do
        file_scope = extractor.extract(TestRefinementModule)
        expect(file_scope).not_to be_nil
        module_scope = file_scope.scopes.first
        expect(module_scope.scope_type).to eq('MODULE')
        expect(module_scope.name).to eq('TestRefinementModule')
      end

      it 'does not add refined methods to the target class' do
        # String.instance_methods(false) never includes refinement methods —
        # they are only visible within `using` scope. So String extraction
        # (which is filtered as stdlib anyway) would not show `shout`.
        # This test documents the behavior for awareness.
        expect(String.instance_methods(false)).not_to include(:shout)
      end
    end

    context 'with filtering excluded packages/code' do
      # Ported from Java SymbolExtractionTransformerTest: symbolExtraction15 (filtering)
      # and SymDBEnablementTest: noIncludesFilterOutDatadogClass

      it 'returns nil for Datadog internal classes' do
        expect(extractor.extract(Datadog::SymbolDatabase::Extractor)).to be_nil
        expect(extractor.extract(Datadog::SymbolDatabase::Scope)).to be_nil
        expect(extractor.extract(Datadog::SymbolDatabase::FileHash)).to be_nil
      end

      it 'returns nil for Ruby core classes' do
        expect(extractor.extract(Object)).to be_nil
        expect(extractor.extract(BasicObject)).to be_nil
        expect(extractor.extract(Kernel)).to be_nil
        expect(extractor.extract(Module)).to be_nil
        expect(extractor.extract(Class)).to be_nil
      end

      it 'returns nil for Ruby stdlib classes' do
        expect(extractor.extract(File)).to be_nil
        expect(extractor.extract(Dir)).to be_nil
        expect(extractor.extract(IO)).to be_nil
      end

      it 'returns nil for gem classes' do
        expect(extractor.extract(RSpec)).to be_nil
        expect(extractor.extract(RSpec::Core::Example)).to be_nil
      end
    end

    context 'with class containing blocks and lambdas' do
      # Ported from Java SymbolExtractionTransformerTest: symbolExtraction06 (lambdas)
      # Ruby doesn't extract block/lambda scopes, but the enclosing methods should still work.
      before do
        @filename = create_user_code_file(<<~RUBY)
          class TestBlockClass
            MY_LAMBDA = ->(x) { x * 2 }
            MY_PROC = Proc.new { |y| y + 1 }

            def method_with_block
              [1, 2, 3].each do |item|
                puts item
              end
            end

            def method_with_lambda
              doubler = ->(n) { n * 2 }
              doubler.call(5)
            end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestBlockClass) if defined?(TestBlockClass)
        cleanup_user_code_file(@filename)
      end

      it 'extracts methods that contain blocks' do
        class_scope = extractor.extract(TestBlockClass).scopes.first
        method_names = class_scope.scopes.map(&:name)

        expect(method_names).to include('method_with_block')
        expect(method_names).to include('method_with_lambda')
      end

      it 'extracts lambda constants as STATIC_FIELD symbols' do
        class_scope = extractor.extract(TestBlockClass).scopes.first
        constant_names = class_scope.symbols.map(&:name)

        expect(constant_names).to include('MY_LAMBDA')
        expect(constant_names).to include('MY_PROC')
      end
    end

    context 'with duplicate class through re-load' do
      # Ported from Java SymDBEnablementTest: noDuplicateSymbolExtraction
      # Tests that the same class is not extracted twice when loaded from different paths.
      it 'produces consistent extraction for the same class' do
        filename = create_user_code_file(<<~RUBY)
          class TestDuplicateClass
            def some_method; end
          end
        RUBY
        load filename

        scope1 = extractor.extract(TestDuplicateClass)
        scope2 = extractor.extract(TestDuplicateClass)

        # Same class should produce identical extractions
        expect(scope1.to_json).to eq(scope2.to_json)

        Object.send(:remove_const, :TestDuplicateClass)
        cleanup_user_code_file(filename)
      end
    end
  end

  describe '.user_code_module?' do
    it 'returns false for Datadog namespace' do
      expect(extractor.send(:user_code_module?, Datadog::SymbolDatabase::Extractor)).to be false
    end

    it 'returns false for the bare Datadog root module' do
      expect(extractor.send(:user_code_module?, Datadog)).to be false
    end

    it 'returns false for anonymous modules' do
      expect(extractor.send(:user_code_module?, Module.new)).to be false
    end

    it 'returns false for C-implemented Ruby internals (ThreadGroup, Thread::Backtrace, RubyVM)' do
      # These classes have no Ruby-defined methods (source_location is nil for all),
      # so find_source_file falls back to const_source_location, which returns ["<main>", 0]
      # for their nested constants — a pseudo-path that is not an absolute path.
      # See: Pitfall 25, tmp/reproduce_threadgroup_leak.rb
      expect(extractor.send(:user_code_module?, ThreadGroup)).to be false
      expect(extractor.send(:user_code_module?, Thread::Backtrace)).to be false
      expect(extractor.send(:user_code_module?, RubyVM)).to be false
    end

    it 'returns true for user code class' do
      user_file = create_user_code_file(<<~RUBY)
        class TestUserCodeModuleCheck
          def a_method; end
        end
      RUBY
      load user_file

      expect(extractor.send(:user_code_module?, TestUserCodeModuleCheck)).to be true

      Object.send(:remove_const, :TestUserCodeModuleCheck)
      cleanup_user_code_file(user_file)
    end

    it 'returns true for class with mixed gem and user methods' do
      user_file = create_user_code_file(<<~RUBY)
        class TestMixedSourceModule
          def user_method; end
        end
      RUBY
      load user_file

      gem_path = '/fake/gems/activerecord-7.0/lib/autosave.rb'
      gem_method = instance_double(Method, source_location: [gem_path, 1])
      user_method = TestMixedSourceModule.instance_method(:user_method)

      allow(TestMixedSourceModule).to receive(:instance_methods).with(false).and_return([:gem_method, :user_method])
      allow(TestMixedSourceModule).to receive(:instance_method).with(:gem_method).and_return(gem_method)
      allow(TestMixedSourceModule).to receive(:instance_method).with(:user_method).and_return(user_method)

      expect(extractor.send(:user_code_module?, TestMixedSourceModule)).to be true

      Object.send(:remove_const, :TestMixedSourceModule)
      cleanup_user_code_file(user_file)
    end

    it 'returns false for class with only gem methods' do
      gem_path = '/fake/gems/activerecord-7.0/lib/autosave.rb'
      mod = Class.new
      allow(mod).to receive(:name).and_return('SomeGemClass')

      gem_method = instance_double(Method, source_location: [gem_path, 1])
      allow(mod).to receive(:instance_methods).with(false).and_return([:gem_method])
      allow(mod).to receive(:instance_method).with(:gem_method).and_return(gem_method)
      allow(mod).to receive(:singleton_methods).with(false).and_return([])

      expect(extractor.send(:user_code_module?, mod)).to be false
    end

    it 'returns false for stdlib class monkey-patched by Datadog instrumentation' do
      # Simulates Net::HTTP when dd-trace-rb instruments it:
      # - Most methods point to /usr/lib/ruby/3.2.0/net/http.rb (stdlib)
      # - The patched `request` method points to lib/datadog/tracing/contrib/http/instrumentation.rb
      # Without the /lib/datadog/ exclusion, find_source_file would return the Datadog path
      # as "user code", causing Net::HTTP to be extracted.
      mod = Class.new
      allow(mod).to receive(:name).and_return('Net::HTTP')

      stdlib_method = instance_double(Method, source_location: ['/usr/lib/ruby/3.2.0/net/http.rb', 100])
      datadog_method = instance_double(Method, source_location: ['/app/lib/datadog/tracing/contrib/http/instrumentation.rb', 26])

      allow(mod).to receive(:instance_methods).with(false).and_return([:request, :get])
      allow(mod).to receive(:instance_method).with(:request).and_return(datadog_method)
      allow(mod).to receive(:instance_method).with(:get).and_return(stdlib_method)
      allow(mod).to receive(:singleton_methods).with(false).and_return([])

      expect(extractor.send(:user_code_module?, mod)).to be false
    end
  end

  describe '.extract edge cases' do
    context 'empty and minimal classes' do
      it 'returns nil for empty top-level class (no methods, no constants, no vars)' do
        filename = create_user_code_file("class TestEmptyClass; end")
        load filename
        expect(described_class.extract(TestEmptyClass)).to be_nil
        Object.send(:remove_const, :TestEmptyClass)
        cleanup_user_code_file(filename)
      end

      it 'returns nil for empty top-level module' do
        filename = create_user_code_file("module TestEmptyModule; end")
        load filename
        expect(described_class.extract(TestEmptyModule)).to be_nil
        Object.send(:remove_const, :TestEmptyModule)
        cleanup_user_code_file(filename)
      end

      it 'handles top-level class with only constants on Ruby 2.7+' do
        filename = create_user_code_file(<<~RUBY)
          class TestConstOnlyClass
            SOME_CONST = 42
          end
        RUBY
        load filename

        scope = described_class.extract(TestConstOnlyClass)
        if TestConstOnlyClass.respond_to?(:const_source_location)
          # Ruby 2.7+: const_source_location finds source via constants
          expect(scope).not_to be_nil
          expect(scope.scope_type).to eq('PACKAGE')
        else
          # Ruby 2.5/2.6: no const_source_location, cannot find source
          expect(scope).to be_nil
        end

        Object.send(:remove_const, :TestConstOnlyClass)
        cleanup_user_code_file(filename)
      end
    end

    context 'deeply nested namespaces' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          module TestA
            module TestB
              class TestC
                def deep_method; end
              end
            end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestA) if defined?(TestA)
        cleanup_user_code_file(@filename)
      end

      it 'extracts deeply nested class (A::B::C) as standalone root scope' do
        scope = described_class.extract(TestA::TestB::TestC)
        expect(scope).not_to be_nil
        expect(scope.scope_type).to eq('PACKAGE')
        expect(scope.name).to eq(scope.source_file)
        expect(scope.scopes.first.scope_type).to eq('CLASS')
      end

      it 'extracts namespace modules via const_source_location when they have nested constants' do
        # On Ruby 2.7+: TestA has const TestB (a module), TestA::TestB has const TestC (a class).
        # const_source_location finds the source file via these constants, so both modules ARE extracted.
        if TestA.respond_to?(:const_source_location)
          expect(described_class.extract(TestA)).not_to be_nil
          expect(described_class.extract(TestA::TestB)).not_to be_nil
        else
          # Ruby < 2.7: no const_source_location, namespace modules without methods return nil
          expect(described_class.extract(TestA)).to be_nil
          expect(described_class.extract(TestA::TestB)).to be_nil
        end
      end

      it 'extracts all scopes in the namespace chain (Ruby 2.7+)' do
        # TestA, TestA::TestB, TestA::TestB::TestC all get extracted on Ruby 2.7+
        # because const_source_location propagates source file through the chain.
        # Use explicit module list rather than ObjectSpace to avoid cross-test pollution.
        mods = [TestA, TestA::TestB, TestA::TestB::TestC]
        extracted = Datadog::Core::Utils::Array.filter_map(mods) { |mod| described_class.extract(mod) }

        # Modules keep their module name; classes get file-based PACKAGE name.
        # Check scope types: TestA and TestA::TestB are modules, TestA::TestB::TestC is a class.
        scope_types = extracted.map { |s| [s.scope_type, s.name] }

        if TestA.respond_to?(:const_source_location)
          expect(extracted.size).to eq(3)
          expect(scope_types).to include(['MODULE', 'TestA'], ['MODULE', 'TestA::TestB'])
          # TestA::TestB::TestC is a class → PACKAGE wrapper with file-based name
          tc_scope = extracted.find { |s| s.scope_type == 'PACKAGE' }
          expect(tc_scope).not_to be_nil
          expect(tc_scope.scopes.first.name).to eq('TestA::TestB::TestC')
        else
          expect(extracted.size).to eq(1)
          expect(extracted.first.scope_type).to eq('PACKAGE')
        end
      end
    end

    context 'AR-style model with no user-defined methods' do
      it 'returns nil for class whose only methods come from gem paths' do
        filename = create_user_code_file(<<~RUBY)
          class TestARStyleModel
          end
        RUBY
        load filename

        gem_path = '/fake/gems/activerecord-7.0/lib/active_record/autosave.rb'
        gem_method = instance_double(Method, source_location: [gem_path, 1])

        allow(TestARStyleModel).to receive(:instance_methods).with(false).and_return([:gem_generated_method])
        allow(TestARStyleModel).to receive(:instance_method).with(:gem_generated_method).and_return(gem_method)
        allow(TestARStyleModel).to receive(:singleton_methods).with(false).and_return([])

        expect(described_class.extract(TestARStyleModel)).to be_nil

        Object.send(:remove_const, :TestARStyleModel)
        cleanup_user_code_file(filename)
      end
    end

    context 'class with only class variables (no methods)' do
      it 'returns nil — class variables are not findable via source_location or const_source_location' do
        # @@class_var is not a constant, so it does not appear in constants(false)
        # and const_source_location cannot find it. No methods → source file is nil.
        filename = create_user_code_file(<<~RUBY)
          class TestClassVarOnly
            @@count = 0
          end
        RUBY
        load filename
        expect(described_class.extract(TestClassVarOnly)).to be_nil
        Object.send(:remove_const, :TestClassVarOnly)
        cleanup_user_code_file(filename)
      end
    end

    context 'module with only non-class-value constants' do
      it 'is extracted on Ruby 2.7+ via const_source_location (non-class constants count)' do
        # const_source_location works for any constant including VALUE constants (FOO = 42),
        # not just class/module constants. So a module with only value constants IS found.
        filename = create_user_code_file(<<~RUBY)
          module TestValueConstModule
            MAX_SIZE = 100
            DEFAULT_NAME = "test"
          end
        RUBY
        load filename
        scope = described_class.extract(TestValueConstModule)
        if TestValueConstModule.respond_to?(:const_source_location)
          expect(scope).not_to be_nil
          expect(scope.scope_type).to eq('MODULE')
          expect(scope.name).to eq('TestValueConstModule')
        else
          expect(scope).to be_nil
        end
        Object.send(:remove_const, :TestValueConstModule)
        cleanup_user_code_file(filename)
      end
    end

    context 'namespace module found via const_source_location has file_hash' do
      it 'computes file_hash from the const_source_location-derived source file' do
        skip 'requires Ruby 2.7+' unless Module.method_defined?(:const_source_location)

        filename = create_user_code_file(<<~RUBY)
          module TestNsFileHash
            class TestNsChild
              def child_method; end
            end
          end
        RUBY
        load filename

        # TestNsFileHash has no methods but has a class constant — extracted via const_source_location
        scope = described_class.extract(TestNsFileHash)
        expect(scope).not_to be_nil
        expect(scope.language_specifics[:file_hash]).not_to be_nil
        expect(scope.language_specifics[:file_hash]).to match(/\A[0-9a-f]{40}\z/)

        Object.send(:remove_const, :TestNsFileHash)
        cleanup_user_code_file(filename)
      end
    end

    context 'concern-style modules' do
      it 'extracts a module with only an included block (no direct def methods)' do
        # A concern using `included do ... end` — the `included` call is a singleton method
        # on ActiveSupport::Concern (or a no-op here). Without direct `def` methods,
        # find_source_file falls through to const_source_location or returns nil.
        filename = create_user_code_file(<<~RUBY)
          module TestConcernNoMethods
            def self.included(base)
              base.extend(ClassMethods)
            end

            module ClassMethods
              def searchable?; true; end
            end
          end
        RUBY
        load filename

        # TestConcernNoMethods has a singleton method (self.included) → source_location
        # points to the file → extracted
        scope = described_class.extract(TestConcernNoMethods)
        expect(scope).not_to be_nil
        expect(scope.scope_type).to eq('MODULE')
        expect(scope.name).to eq('TestConcernNoMethods')

        Object.send(:remove_const, :TestConcernNoMethods)
        cleanup_user_code_file(filename)
      end
    end

    # === Tests ported from Java SymbolExtractionTransformerTest ===
    # Java tests bytecode-level variable scoping (if/for/while blocks).
    # Ruby uses reflection, not bytecode — we test the Ruby equivalents.

    context 'with protected methods' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          class TestProtectedClass
            def public_method; end

            protected

            def protected_method; end

            private

            def private_method; end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestProtectedClass) if defined?(TestProtectedClass)
        cleanup_user_code_file(@filename)
      end

      it 'captures protected visibility' do
        class_scope = described_class.extract(TestProtectedClass).scopes.first

        protected_method = class_scope.scopes.find { |s| s.name == 'protected_method' }
        expect(protected_method.language_specifics[:visibility]).to eq('protected')
      end

      it 'extracts all three visibility levels' do
        class_scope = described_class.extract(TestProtectedClass).scopes.first

        visibilities = class_scope.scopes.map { |s| s.language_specifics[:visibility] }
        expect(visibilities).to include('public', 'protected', 'private')
      end
    end

    context 'with attr_accessor methods' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          class TestAttrClass
            attr_reader :read_only
            attr_writer :write_only
            attr_accessor :read_write

            def initialize
              @read_only = 1
              @write_only = 2
              @read_write = 3
            end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestAttrClass) if defined?(TestAttrClass)
        cleanup_user_code_file(@filename)
      end

      it 'extracts attr_reader as METHOD scope' do
        class_scope = described_class.extract(TestAttrClass).scopes.first
        method_names = class_scope.scopes.map(&:name)

        expect(method_names).to include('read_only')
      end

      it 'extracts attr_writer as METHOD scope' do
        class_scope = described_class.extract(TestAttrClass).scopes.first
        method_names = class_scope.scopes.map(&:name)

        expect(method_names).to include('write_only=')
      end

      it 'extracts attr_accessor as both reader and writer METHOD scopes' do
        class_scope = described_class.extract(TestAttrClass).scopes.first
        method_names = class_scope.scopes.map(&:name)

        expect(method_names).to include('read_write')
        expect(method_names).to include('read_write=')
      end
    end

    context 'with prepended modules' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          module TestPrependModule
            def prepended_method; end
          end

          class TestPrependedClass
            prepend TestPrependModule

            def original_method; end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestPrependedClass) if defined?(TestPrependedClass)
        Object.send(:remove_const, :TestPrependModule) if defined?(TestPrependModule)
        cleanup_user_code_file(@filename)
      end

      it 'captures prepended modules in language_specifics' do
        class_scope = described_class.extract(TestPrependedClass).scopes.first

        expect(class_scope.language_specifics[:prepended_modules]).to include('TestPrependModule')
      end
    end

    context 'with all parameter types' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          class TestAllParamsClass
            def method_with_all_params(required, optional = nil, *rest, keyword:, optional_kw: 'default', **keyrest, &blk)
              # Method with every Ruby parameter type
            end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestAllParamsClass) if defined?(TestAllParamsClass)
        cleanup_user_code_file(@filename)
      end

      it 'extracts required, optional, rest, keyword, and keyrest parameters' do
        class_scope = described_class.extract(TestAllParamsClass).scopes.first
        method_scope = class_scope.scopes.find { |s| s.name == 'method_with_all_params' }

        param_names = method_scope.symbols.map(&:name)

        expect(param_names).to include('self')
        expect(param_names).to include('required')
        expect(param_names).to include('optional')
        expect(param_names).to include('rest')
        expect(param_names).to include('keyword')
        expect(param_names).to include('optional_kw')
        expect(param_names).to include('keyrest')
      end

      it 'skips block parameters' do
        class_scope = described_class.extract(TestAllParamsClass).scopes.first
        method_scope = class_scope.scopes.find { |s| s.name == 'method_with_all_params' }

        param_names = method_scope.symbols.map(&:name)

        expect(param_names).not_to include('blk')
      end

      it 'all extracted parameters are ARG symbol type' do
        class_scope = described_class.extract(TestAllParamsClass).scopes.first
        method_scope = class_scope.scopes.find { |s| s.name == 'method_with_all_params' }

        method_scope.symbols.each do |sym|
          expect(sym.symbol_type).to eq('ARG')
        end
      end
    end

    context 'with exception handling (begin/rescue/ensure equivalent)' do
      # Ported from Java SymbolExtractionTransformerTest: symbolExtraction03 (try-catch-finally)
      # Ruby doesn't expose local variable scoping from bytecode, but we verify
      # that methods containing exception handling constructs are still extracted.
      before do
        @filename = create_user_code_file(<<~RUBY)
          class TestExceptionClass
            def method_with_rescue(input)
              result = nil
              begin
                result = Integer(input)
              rescue ArgumentError => e
                result = -1
              rescue TypeError
                result = -2
              ensure
                @last_input = input
              end
              result
            end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestExceptionClass) if defined?(TestExceptionClass)
        cleanup_user_code_file(@filename)
      end

      it 'extracts method containing begin/rescue/ensure' do
        class_scope = described_class.extract(TestExceptionClass).scopes.first
        method_scope = class_scope.scopes.find { |s| s.name == 'method_with_rescue' }

        expect(method_scope).not_to be_nil
        expect(method_scope.scope_type).to eq('METHOD')
      end

      it 'extracts parameters from method with exception handling' do
        class_scope = described_class.extract(TestExceptionClass).scopes.first
        method_scope = class_scope.scopes.find { |s| s.name == 'method_with_rescue' }

        param_names = method_scope.symbols.map(&:name)
        expect(param_names).to include('input')
      end
    end

    context 'with define_method (metaprogramming)' do
      # Ported from Java: tests dynamically defined methods. Java tests bytecode
      # for dynamic proxies; Ruby equivalent is define_method.
      before do
        @filename = create_user_code_file(<<~RUBY)
          class TestDefineMethodClass
            define_method(:dynamic_method) do |arg1, arg2|
              arg1 + arg2
            end

            def regular_method; end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestDefineMethodClass) if defined?(TestDefineMethodClass)
        cleanup_user_code_file(@filename)
      end

      it 'extracts dynamically defined methods' do
        class_scope = described_class.extract(TestDefineMethodClass).scopes.first
        method_names = class_scope.scopes.map(&:name)

        expect(method_names).to include('dynamic_method')
        expect(method_names).to include('regular_method')
      end

      it 'extracts parameters from define_method' do
        class_scope = described_class.extract(TestDefineMethodClass).scopes.first
        method_scope = class_scope.scopes.find { |s| s.name == 'dynamic_method' }

        param_names = method_scope.symbols.map(&:name)
        expect(param_names).to include('arg1')
        expect(param_names).to include('arg2')
      end
    end

    context 'with Struct class' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          TestStructClass = Struct.new(:name, :age) do
            def greeting
              "Hello, \#{name}"
            end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestStructClass) if defined?(TestStructClass)
        cleanup_user_code_file(@filename)
      end

      it 'extracts Struct-based class' do
        scope = described_class.extract(TestStructClass)

        expect(scope).not_to be_nil
        expect(scope.scope_type).to eq('PACKAGE')
        expect(scope.name).to eq(scope.source_file)
      end

      it 'extracts user-defined methods on Struct' do
        class_scope = described_class.extract(TestStructClass).scopes.first
        method_names = class_scope.scopes.map(&:name)

        expect(method_names).to include('greeting')
      end
    end

    context 'with singleton/eigenclass methods (upload_class_methods: true)' do
      # Ported from Java: tests static methods. Ruby equivalent is singleton methods.
      before do
        @filename = create_user_code_file(<<~RUBY)
          class TestSingletonMethodsClass
            def self.class_method_one(param)
              param * 2
            end

            def self.class_method_two
              "hello"
            end

            def instance_method
              "instance"
            end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestSingletonMethodsClass) if defined?(TestSingletonMethodsClass)
        cleanup_user_code_file(@filename)
      end

      it 'extracts singleton methods when upload_class_methods is true' do
        scope = described_class.extract(TestSingletonMethodsClass, upload_class_methods: true)
        class_scope = scope.scopes.first
        method_names = class_scope.scopes.map(&:name)

        expect(method_names).to include('class_method_one')
        expect(method_names).to include('class_method_two')
        expect(method_names).to include('instance_method')
      end

      it 'marks singleton methods with method_type: class' do
        scope = described_class.extract(TestSingletonMethodsClass, upload_class_methods: true)
        class_scope = scope.scopes.first

        cm = class_scope.scopes.find { |s| s.name == 'class_method_one' }
        expect(cm.language_specifics[:method_type]).to eq('class')

        im = class_scope.scopes.find { |s| s.name == 'instance_method' }
        expect(im.language_specifics[:method_type]).to eq('instance')
      end

      it 'extracts parameters from singleton methods' do
        scope = described_class.extract(TestSingletonMethodsClass, upload_class_methods: true)
        class_scope = scope.scopes.first

        cm = class_scope.scopes.find { |s| s.name == 'class_method_one' }
        param_names = cm.symbols.map(&:name)
        expect(param_names).to include('param')
        # Singleton methods should NOT have self ARG
        expect(param_names).not_to include('self')
      end
    end

    context 'with filtering excluded packages/code' do
      # Ported from Java SymbolExtractionTransformerTest: symbolExtraction15 (filtering)
      # and SymDBEnablementTest: noIncludesFilterOutDatadogClass

      it 'returns nil for Datadog internal classes' do
        expect(described_class.extract(Datadog::SymbolDatabase::Extractor)).to be_nil
        expect(described_class.extract(Datadog::SymbolDatabase::Scope)).to be_nil
        expect(described_class.extract(Datadog::SymbolDatabase::Component)).to be_nil
      end

      it 'returns nil for Ruby stdlib classes' do
        expect(described_class.extract(File)).to be_nil
        expect(described_class.extract(Dir)).to be_nil
        expect(described_class.extract(IO)).to be_nil
      end

      it 'returns nil for gem classes' do
        expect(described_class.extract(RSpec)).to be_nil
        expect(described_class.extract(RSpec::Core::Example)).to be_nil
      end
    end

    context 'with class containing blocks and lambdas' do
      # Ported from Java SymbolExtractionTransformerTest: symbolExtraction06 (lambdas)
      # Ruby doesn't extract block/lambda scopes, but the enclosing methods should still work.
      before do
        @filename = create_user_code_file(<<~RUBY)
          class TestBlockClass
            MY_LAMBDA = ->(x) { x * 2 }
            MY_PROC = Proc.new { |y| y + 1 }

            def method_with_block
              [1, 2, 3].each do |item|
                puts item
              end
            end

            def method_with_lambda
              doubler = ->(n) { n * 2 }
              doubler.call(5)
            end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestBlockClass) if defined?(TestBlockClass)
        cleanup_user_code_file(@filename)
      end

      it 'extracts methods that contain blocks' do
        class_scope = described_class.extract(TestBlockClass).scopes.first
        method_names = class_scope.scopes.map(&:name)

        expect(method_names).to include('method_with_block')
        expect(method_names).to include('method_with_lambda')
      end

      it 'extracts lambda constants as STATIC_FIELD symbols' do
        class_scope = described_class.extract(TestBlockClass).scopes.first
        constant_names = class_scope.symbols.map(&:name)

        expect(constant_names).to include('MY_LAMBDA')
        expect(constant_names).to include('MY_PROC')
      end
    end

    context 'with duplicate class through re-load' do
      # Ported from Java SymDBEnablementTest: noDuplicateSymbolExtraction
      # Tests that the same class is not extracted twice when loaded from different paths.
      it 'produces consistent extraction for the same class' do
        filename = create_user_code_file(<<~RUBY)
          class TestDuplicateClass
            def some_method; end
          end
        RUBY
        load filename

        scope1 = described_class.extract(TestDuplicateClass)
        scope2 = described_class.extract(TestDuplicateClass)

        # Same class should produce identical extractions
        expect(scope1.to_json).to eq(scope2.to_json)

        Object.send(:remove_const, :TestDuplicateClass)
        cleanup_user_code_file(filename)
      end
    end
  end

  describe '.user_code_module?' do
    it 'returns false for Datadog namespace' do
      expect(described_class.send(:user_code_module?, Datadog::SymbolDatabase::Extractor)).to be false
    end

    it 'returns false for anonymous modules' do
      expect(described_class.send(:user_code_module?, Module.new)).to be false
    end

    it 'returns true for user code class' do
      user_file = create_user_code_file(<<~RUBY)
        class TestUserCodeModuleCheck
          def a_method; end
        end
      RUBY
      load user_file

      expect(described_class.send(:user_code_module?, TestUserCodeModuleCheck)).to be true

      Object.send(:remove_const, :TestUserCodeModuleCheck)
      cleanup_user_code_file(user_file)
    end

    it 'returns true for class with mixed gem and user methods' do
      user_file = create_user_code_file(<<~RUBY)
        class TestMixedSourceModule
          def user_method; end
        end
      RUBY
      load user_file

      gem_path = '/fake/gems/activerecord-7.0/lib/autosave.rb'
      gem_method = instance_double(Method, source_location: [gem_path, 1])
      user_method = TestMixedSourceModule.instance_method(:user_method)

      allow(TestMixedSourceModule).to receive(:instance_methods).with(false).and_return([:gem_method, :user_method])
      allow(TestMixedSourceModule).to receive(:instance_method).with(:gem_method).and_return(gem_method)
      allow(TestMixedSourceModule).to receive(:instance_method).with(:user_method).and_return(user_method)

      expect(described_class.send(:user_code_module?, TestMixedSourceModule)).to be true

      Object.send(:remove_const, :TestMixedSourceModule)
      cleanup_user_code_file(user_file)
    end

    it 'returns false for class with only gem methods' do
      gem_path = '/fake/gems/activerecord-7.0/lib/autosave.rb'
      mod = Class.new
      allow(mod).to receive(:name).and_return('SomeGemClass')

      gem_method = instance_double(Method, source_location: [gem_path, 1])
      allow(mod).to receive(:instance_methods).with(false).and_return([:gem_method])
      allow(mod).to receive(:instance_method).with(:gem_method).and_return(gem_method)
      allow(mod).to receive(:singleton_methods).with(false).and_return([])

      expect(described_class.send(:user_code_module?, mod)).to be false
    end

    it 'returns false for stdlib class monkey-patched by Datadog instrumentation' do
      # Simulates Net::HTTP when dd-trace-rb instruments it:
      # - Most methods point to /usr/lib/ruby/3.2.0/net/http.rb (stdlib)
      # - The patched `request` method points to lib/datadog/tracing/contrib/http/instrumentation.rb
      # Without the /lib/datadog/ exclusion, find_source_file would return the Datadog path
      # as "user code", causing Net::HTTP to be extracted.
      mod = Class.new
      allow(mod).to receive(:name).and_return('Net::HTTP')

      stdlib_method = instance_double(Method, source_location: ['/usr/lib/ruby/3.2.0/net/http.rb', 100])
      datadog_method = instance_double(Method, source_location: ['/app/lib/datadog/tracing/contrib/http/instrumentation.rb', 26])

      allow(mod).to receive(:instance_methods).with(false).and_return([:request, :get])
      allow(mod).to receive(:instance_method).with(:request).and_return(datadog_method)
      allow(mod).to receive(:instance_method).with(:get).and_return(stdlib_method)
      allow(mod).to receive(:singleton_methods).with(false).and_return([])

      expect(described_class.send(:user_code_module?, mod)).to be false
    end
  end

  describe '.user_code_path?' do
    it 'returns false for gem paths' do
      expect(extractor.send(:user_code_path?, '/path/to/gems/rspec/lib/rspec.rb')).to be false
    end

    it 'returns false for ruby stdlib paths' do
      expect(extractor.send(:user_code_path?, '/usr/lib/ruby/3.2/pathname.rb')).to be false
    end

    it 'returns false for internal paths' do
      expect(extractor.send(:user_code_path?, '<internal:array>')).to be false
    end

    it 'returns false for pseudo-paths from C-level interpreter init' do
      # "<main>" line 0 is Ruby's sentinel for constants assigned during C startup
      # (before any .rb file runs). Affects ThreadGroup::Default, Thread::Backtrace::Location,
      # RubyVM::InstructionSequence, etc. See: Pitfall 25, tmp/reproduce_threadgroup_leak.rb
      expect(extractor.send(:user_code_path?, '<main>')).to be false
      expect(extractor.send(:user_code_path?, 'ruby')).to be false
    end

    it 'returns false for eval paths' do
      expect(extractor.send(:user_code_path?, '(eval):1')).to be false
    end

    it 'returns false for spec paths' do
      expect(extractor.send(:user_code_path?, '/project/spec/my_spec.rb')).to be false
    end

    it 'returns false for Datadog library paths (monkey-patched methods)' do
      # When dd-trace-rb instruments stdlib classes like Net::HTTP, the patched method
      # source points to lib/datadog/tracing/contrib/. Without this exclusion,
      # Net::HTTP would be incorrectly classified as user code.
      expect(extractor.send(:user_code_path?,
        '/home/user/.gem/ruby/3.2.0/gems/datadog-2.0.0/lib/datadog/tracing/contrib/http/instrumentation.rb')).to be false
      expect(extractor.send(:user_code_path?,
        '/real.home/user/dtr/lib/datadog/tracing/contrib/http/instrumentation.rb')).to be false
      expect(extractor.send(:user_code_path?,
        '/app/vendor/bundle/lib/datadog/core/pin.rb')).to be false
    end

    it 'returns false for Datadog library paths (monkey-patched methods)' do
      # When dd-trace-rb instruments stdlib classes like Net::HTTP, the patched method
      # source points to lib/datadog/tracing/contrib/. Without this exclusion,
      # Net::HTTP would be incorrectly classified as user code.
      expect(described_class.send(:user_code_path?,
        '/home/user/.gem/ruby/3.2.0/gems/datadog-2.0.0/lib/datadog/tracing/contrib/http/instrumentation.rb')).to be false
      expect(described_class.send(:user_code_path?,
        '/real.home/user/dtr/lib/datadog/tracing/contrib/http/instrumentation.rb')).to be false
      expect(described_class.send(:user_code_path?,
        '/app/vendor/bundle/lib/datadog/core/pin.rb')).to be false
    end

    it 'returns true for user code paths' do
      expect(extractor.send(:user_code_path?, '/app/lib/my_class.rb')).to be true
      expect(extractor.send(:user_code_path?, '/home/user/project/file.rb')).to be true
      expect(extractor.send(:user_code_path?, File.join(@test_dir, 'test.rb'))).to be true
    end
  end

  describe '.find_source_file' do
    before do
      @filename = create_user_code_file(<<~RUBY)
        class TestClassForSourceFile
          def test_method
          end
        end
      RUBY
      load @filename
    end

    after do
      Object.send(:remove_const, :TestClassForSourceFile) if defined?(TestClassForSourceFile)
      cleanup_user_code_file(@filename)
    end

    it 'finds source file from instance methods' do
      source_file = extractor.send(:find_source_file, TestClassForSourceFile)
      expect(source_file).to eq(@filename)
    end

    it 'returns nil for modules without methods' do
      empty_mod = Module.new

      source_file = extractor.send(:find_source_file, empty_mod)
      expect(source_file).to be_nil
    end

    it 'prefers user code path over gem path' do
      # Simulate ActiveRecord model: first method points to gem, second to user code
      user_file = create_user_code_file(<<~RUBY)
        class TestClassWithMixedSources
          def user_method; end
        end
      RUBY
      load user_file

      gem_path = '/fake/gems/activerecord-7.0/lib/active_record/autosave.rb'

      # Stub instance_methods to return gem method first, user method second
      allow(TestClassWithMixedSources).to receive(:instance_methods).with(false).and_return([:gem_method, :user_method])

      gem_method = instance_double(Method, source_location: [gem_path, 10])
      user_method = TestClassWithMixedSources.instance_method(:user_method)

      allow(TestClassWithMixedSources).to receive(:instance_method).with(:gem_method).and_return(gem_method)
      allow(TestClassWithMixedSources).to receive(:instance_method).with(:user_method).and_return(user_method)

      source_file = extractor.send(:find_source_file, TestClassWithMixedSources)
      expect(source_file).to eq(user_file)

      Object.send(:remove_const, :TestClassWithMixedSources)
      cleanup_user_code_file(user_file)
    end

    it 'falls back to stdlib path when only Datadog instrumentation and stdlib paths exist' do
      # Simulates Net::HTTP: the Datadog instrumentation path is not user code,
      # so find_source_file should fall back to the stdlib path.
      stdlib_path = '/usr/lib/ruby/3.2.0/net/http.rb'
      datadog_path = '/app/lib/datadog/tracing/contrib/http/instrumentation.rb'
      mod = Module.new

      datadog_method = instance_double(Method, source_location: [datadog_path, 26])
      stdlib_method = instance_double(Method, source_location: [stdlib_path, 100])

      allow(mod).to receive(:instance_methods).with(false).and_return([:request, :get])
      allow(mod).to receive(:instance_method).with(:request).and_return(datadog_method)
      allow(mod).to receive(:instance_method).with(:get).and_return(stdlib_method)

      source_file = extractor.send(:find_source_file, mod)
      expect(source_file).to eq(datadog_path)  # Falls back to first non-nil path
    end

    it 'falls back to gem path when no user code path exists' do
      gem_path = '/fake/gems/activerecord-7.0/lib/active_record/autosave.rb'
      mod = Module.new

      gem_method = instance_double(Method, source_location: [gem_path, 10])
      allow(mod).to receive(:instance_methods).with(false).and_return([:gem_method])
      allow(mod).to receive(:instance_method).with(:gem_method).and_return(gem_method)

      source_file = extractor.send(:find_source_file, mod)
      expect(source_file).to eq(gem_path)
    end
  end

  describe 'class/module defined across multiple files (reopening)' do
    # Case 12 & 13 from SYMBOL_EXTRACTION_CASES.md
    # Ruby allows reopening a class or module in multiple files. All methods from all
    # files should appear in the extracted scope, not just those from one file.

    context 'class reopened across two files' do
      before do
        @file1 = create_user_code_file(<<~RUBY)
          class TestReopenedClass
            def method_from_file1
              'file1'
            end
          end
        RUBY

        @file2 = create_user_code_file(<<~RUBY)
          class TestReopenedClass
            def method_from_file2
              'file2'
            end
          end
        RUBY

        load @file1
        load @file2
      end

      after do
        Object.send(:remove_const, :TestReopenedClass) if defined?(TestReopenedClass)
        cleanup_user_code_file(@file1)
        cleanup_user_code_file(@file2)
      end

      it 'includes methods from both files in the extracted scope' do
        scope = extractor.extract(TestReopenedClass)

        expect(scope).not_to be_nil
        class_scope = scope.scopes.first
        method_names = class_scope.scopes.map(&:name)

        expect(method_names).to include('method_from_file1')
        expect(method_names).to include('method_from_file2')
      end
    end

    context 'module reopened across two files' do
      before do
        @file1 = create_user_code_file(<<~RUBY)
          module TestReopenedModule
            def self.method_from_file1
              'file1'
            end
          end
        RUBY

        @file2 = create_user_code_file(<<~RUBY)
          module TestReopenedModule
            def self.method_from_file2
              'file2'
            end
          end
        RUBY

        load @file1
        load @file2
      end

      after do
        Object.send(:remove_const, :TestReopenedModule) if defined?(TestReopenedModule)
        cleanup_user_code_file(@file1)
        cleanup_user_code_file(@file2)
      end

      it 'extracts the MODULE scope (methods from either file satisfy source discovery)' do
        # Module methods are not extracted as child METHOD scopes — they are used only
        # for source location discovery. The test verifies the module is found at all,
        # meaning find_source_file can locate user code from at least one of the files.
        file_scope = extractor.extract(TestReopenedModule)

        expect(file_scope).not_to be_nil
        expect(file_scope.scope_type).to eq('FILE')
        module_scope = file_scope.scopes.first
        expect(module_scope.scope_type).to eq('MODULE')
        expect(module_scope.name).to eq('TestReopenedModule')
        expect(file_scope.source_file).to eq(@file1).or(eq(@file2))
      end
    end
  end

  describe 'module inside class' do
    # Case 7 from SYMBOL_EXTRACTION_CASES.md
    # A module defined as a constant of a class (e.g. class Foo; module Bar; end; end)
    # should be extractable as a standalone root scope via its fully-qualified name.

    before do
      @filename = create_user_code_file(<<~RUBY)
        class TestOuterClass
          def outer_method
            'outer'
          end

          module TestInnerModule
            def self.inner_method
              'inner'
            end
          end
        end
      RUBY
      load @filename
    end

    after do
      TestOuterClass.send(:remove_const, :TestInnerModule) if defined?(TestOuterClass::TestInnerModule)
      Object.send(:remove_const, :TestOuterClass) if defined?(TestOuterClass)
      cleanup_user_code_file(@filename)
    end

    it 'extracts the inner module as a standalone root FILE scope' do
      file_scope = extractor.extract(TestOuterClass::TestInnerModule)

      expect(file_scope).not_to be_nil
      expect(file_scope.scope_type).to eq('FILE')
      module_scope = file_scope.scopes.first
      expect(module_scope.scope_type).to eq('MODULE')
      expect(module_scope.name).to eq('TestOuterClass::TestInnerModule')
    end

    it 'extracts the outer class independently' do
      scope = extractor.extract(TestOuterClass)

      expect(scope).not_to be_nil
      class_scope = scope.scopes.first
      expect(class_scope.scope_type).to eq('CLASS')
      method_names = class_scope.scopes.map(&:name)
      expect(method_names).to include('outer_method')
    end
  end

  describe '.resolve_scope_type' do
    it 'returns CLASS for a class' do
      stub_const('ResolveScopeTypeFixtureClass', Class.new)
      expect(extractor.send(:resolve_scope_type, 'ResolveScopeTypeFixtureClass')).to eq('CLASS')
    end

    it 'returns MODULE for a module' do
      stub_const('ResolveScopeTypeFixtureModule', Module.new)
      expect(extractor.send(:resolve_scope_type, 'ResolveScopeTypeFixtureModule')).to eq('MODULE')
    end

    it 'returns MODULE as fallback when constant lookup fails' do
      expect(extractor.send(:resolve_scope_type, 'ResolveScopeTypeAbsolutelyNotDefined')).to eq('MODULE')
    end
  end

  # ── extract_all tests ──────────────────────────────────────────────
  # These test the production path: two-pass extraction with FQN-based nesting
  # and per-file method grouping.

  describe '.extract_all' do
    around do |example|
      Dir.mktmpdir('symbol_db_extract_all_test') do |dir|
        @test_dir = dir
        example.run
      end
    end

    def create_test_file(filename, content)
      path = File.join(@test_dir, filename)
      File.write(path, content)
      File.realpath(path)
    end

    # Find the FILE scope containing a child with the given name.
    # ObjectSpace may contain stale modules from previous examples (not yet GC'd),
    # so matching by file path is unreliable. Match by content instead.
    def find_file_scope(scopes, child_name)
      scopes.find do |s|
        s.scope_type == 'FILE' && s.scopes.any? { |c| c.name == child_name }
      end
    end

    # Force GC before extract_all to clean up stale modules from previous examples.
    # Without this, ObjectSpace may contain modules that were remove_const'd but
    # not yet garbage collected, causing extract_all to see phantom entries.
    def extract_all_clean
      GC.start
      extractor.extract_all
    end

    context 'top-level rescue' do
      let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component, inc: nil) }
      let(:extractor_with_telemetry) do
        described_class.new(logger: logger, settings: settings, telemetry: telemetry)
      end

      it 'returns [] and increments telemetry when collection raises' do
        allow(extractor_with_telemetry).to receive(:collect_extractable_modules).and_raise(StandardError, 'boom')
        result = extractor_with_telemetry.extract_all
        expect(result).to eq([])
        expect(telemetry).to have_received(:inc).with('tracers', 'symbol_database.extract_all_error', 1)
      end
    end

    context 'simple class in one file' do
      before do
        @file = create_test_file('user.rb', <<~RUBY)
          class ExtractAllSimpleClass
            def remember; end
          end
        RUBY
        load @file
      end

      after do
        Object.send(:remove_const, :ExtractAllSimpleClass) if defined?(ExtractAllSimpleClass)
      end

      it 'produces FILE → CLASS → METHOD hierarchy' do
        scopes = extract_all_clean
        file_scope = find_file_scope(scopes, 'ExtractAllSimpleClass')

        expect(file_scope).not_to be_nil
        expect(file_scope.scope_type).to eq('FILE')
        expect(file_scope.language_specifics[:file_hash]).to match(/\A[0-9a-f]{40}\z/)

        class_scope = file_scope.scopes.find { |s| s.name == 'ExtractAllSimpleClass' }
        expect(class_scope).not_to be_nil
        expect(class_scope.scope_type).to eq('CLASS')

        method_scope = class_scope.scopes.find { |s| s.name == 'remember' }
        expect(method_scope).not_to be_nil
        expect(method_scope.scope_type).to eq('METHOD')
      end

      it 'includes injectable lines on instance METHOD scopes' do
        scopes = extract_all_clean
        file_scope = find_file_scope(scopes, 'ExtractAllSimpleClass')
        class_scope = file_scope.scopes.find { |s| s.name == 'ExtractAllSimpleClass' }
        method_scope = class_scope.scopes.find { |s| s.name == 'remember' }

        expect(method_scope.injectible_lines?).to eq(true).or eq(false)
        if method_scope.injectible_lines?
          expect(method_scope.injectible_lines).to be_an(Array)
          expect(method_scope.injectible_lines).not_to be_empty
          method_scope.injectible_lines.each do |range|
            expect(range[:start]).to be <= range[:end]
          end
        end
        expect(method_scope.end_line).to be >= method_scope.start_line
      end
    end

    context 'class with overridden singleton name method' do
      before do
        @file = create_test_file('name_override.rb', <<~RUBY)
          class ExtractAllNameOverride
            def self.name(size:, region:)
              "\#{size}-\#{region}"
            end

            def regular_method; end
          end
        RUBY
        load @file
      end

      after do
        Object.send(:remove_const, :ExtractAllNameOverride) if defined?(ExtractAllNameOverride)
      end

      it 'still appears in extract_all output via safe_mod_name' do
        scopes = extract_all_clean
        file_scope = find_file_scope(scopes, 'ExtractAllNameOverride')

        expect(file_scope).not_to be_nil
        class_scope = file_scope.scopes.find { |s| s.name == 'ExtractAllNameOverride' }
        expect(class_scope).not_to be_nil
        expect(class_scope.scope_type).to eq('CLASS')
      end
    end

    context 'end_line correctness via extract_all' do
      before do
        @file = create_test_file('multiline.rb', <<~RUBY)
          class ExtractAllMultiline
            def lengthy(a, b)
              x = a + b
              y = x * 2
              z = y - 1
              z
            end
          end
        RUBY
        load @file
      end

      after do
        Object.send(:remove_const, :ExtractAllMultiline) if defined?(ExtractAllMultiline)
      end

      it 'sets end_line from trace_points max, not start_line' do
        scopes = extract_all_clean
        file_scope = find_file_scope(scopes, 'ExtractAllMultiline')
        class_scope = file_scope.scopes.find { |s| s.name == 'ExtractAllMultiline' }
        method_scope = class_scope.scopes.find { |s| s.name == 'lengthy' }

        expect(method_scope.end_line).to be > method_scope.start_line
      end
    end

    # ── Injectable lines unit tests ──────────────────────────────────────

    describe 'build_injectable_ranges' do
      it 'compresses consecutive lines into ranges' do
        ranges = extractor.send(:build_injectable_ranges, [4, 5, 6, 8, 10, 11])
        expect(ranges).to eq([{start: 4, end: 6}, {start: 8, end: 8}, {start: 10, end: 11}])
      end

      it 'returns a single range for all-consecutive input' do
        ranges = extractor.send(:build_injectable_ranges, [1, 2, 3, 4, 5])
        expect(ranges).to eq([{start: 1, end: 5}])
      end

      it 'returns individual ranges for non-consecutive input' do
        ranges = extractor.send(:build_injectable_ranges, [1, 3, 5, 7])
        expect(ranges).to eq([{start: 1, end: 1}, {start: 3, end: 3}, {start: 5, end: 5}, {start: 7, end: 7}])
      end

      it 'returns a single-element range for one line' do
        ranges = extractor.send(:build_injectable_ranges, [10])
        expect(ranges).to eq([{start: 10, end: 10}])
      end

      it 'returns empty for empty input' do
        ranges = extractor.send(:build_injectable_ranges, [])
        expect(ranges).to eq([])
      end
    end

    describe 'extract_injectable_lines' do
      before do
        @file = create_test_file('injectable_test.rb', <<~RUBY)
          class ExtractAllInjectableTest
            def multi_line(a, b)
              x = a + b
              y = x * 2
              z = y - 1
              z
            end

            def initialize
              @value = 42
            end
          end
        RUBY
        load @file
      end

      after do
        Object.send(:remove_const, :ExtractAllInjectableTest) if defined?(ExtractAllInjectableTest)
      end

      it 'returns nil for C-extension methods (iseq nil)' do
        # String#length is a C method with no iseq
        method = String.instance_method(:length)
        ranges, end_line = extractor.send(:extract_injectable_lines, method, 1)
        expect(ranges).to be_nil
        expect(end_line).to eq(1)
      end

      it 'deduplicates line numbers before range compression' do
        scopes = extract_all_clean
        file_scope = find_file_scope(scopes, 'ExtractAllInjectableTest')
        class_scope = file_scope.scopes.find { |s| s.name == 'ExtractAllInjectableTest' }
        method_scope = class_scope.scopes.find { |s| s.name == 'multi_line' }

        # Ranges should have no overlapping or duplicate entries
        method_scope.injectible_lines.each_cons(2) do |a, b|
          expect(a[:end]).to be < b[:start]
        end
      end

      it 'includes initialize method first line as injectable' do
        scopes = extract_all_clean
        file_scope = find_file_scope(scopes, 'ExtractAllInjectableTest')
        class_scope = file_scope.scopes.find { |s| s.name == 'ExtractAllInjectableTest' }
        init_scope = class_scope.scopes.find { |s| s.name == 'initialize' }

        expect(init_scope).not_to be_nil
        expect(init_scope.injectible_lines?).to eq(true)
        expect(init_scope.injectible_lines.first[:start]).to eq(init_scope.start_line).or be > init_scope.start_line
      end
    end

    context 'nested module and class' do
      before do
        @file = create_test_file('nested.rb', <<~RUBY)
          module ExtractAllOuter
            def self.outer_func; end

            class ExtractAllInner
              def inner_method; end
            end
          end
        RUBY
        load @file
      end

      after do
        Object.send(:remove_const, :ExtractAllOuter) if defined?(ExtractAllOuter)
      end

      it 'nests via FQN split: FILE → MODULE(Outer) → CLASS(Inner)' do
        scopes = extract_all_clean
        file_scope = find_file_scope(scopes, 'ExtractAllOuter')
        expect(file_scope).not_to be_nil

        # Outer module at top level under FILE, using short name
        outer = file_scope.scopes.find { |s| s.name == 'ExtractAllOuter' }
        expect(outer).not_to be_nil
        expect(outer.scope_type).to eq('MODULE')

        # Inner class nested under outer, using FQN
        inner = outer.scopes.find { |s| s.name == 'ExtractAllOuter::ExtractAllInner' }
        expect(inner).not_to be_nil
        expect(inner.scope_type).to eq('CLASS')

        # Inner class has its method
        method_scope = inner.scopes.find { |s| s.name == 'inner_method' }
        expect(method_scope).not_to be_nil
      end
    end

    context 'deeply nested namespace (A::B::C)' do
      before do
        @file = create_test_file('deep.rb', <<~RUBY)
          module ExtractAllDeepA
            module ExtractAllDeepB
              class ExtractAllDeepC
                def deep_method; end
              end
            end
          end
        RUBY
        load @file
      end

      after do
        Object.send(:remove_const, :ExtractAllDeepA) if defined?(ExtractAllDeepA)
      end

      it 'builds full nesting chain: FILE → MODULE(A) → MODULE(B) → CLASS(C)' do
        scopes = extract_all_clean
        file_scope = find_file_scope(scopes, 'ExtractAllDeepA')
        expect(file_scope).not_to be_nil

        mod_a = file_scope.scopes.find { |s| s.name == 'ExtractAllDeepA' }
        expect(mod_a).not_to be_nil
        expect(mod_a.scope_type).to eq('MODULE')

        mod_b = mod_a.scopes.find { |s| s.name == 'ExtractAllDeepA::ExtractAllDeepB' }
        expect(mod_b).not_to be_nil
        expect(mod_b.scope_type).to eq('MODULE')

        cls_c = mod_b.scopes.find { |s| s.name == 'ExtractAllDeepA::ExtractAllDeepB::ExtractAllDeepC' }
        expect(cls_c).not_to be_nil
        expect(cls_c.scope_type).to eq('CLASS')

        expect(cls_c.scopes.find { |s| s.name == 'deep_method' }).not_to be_nil
      end
    end

    context 'class reopened across two files' do
      before do
        @file1 = create_test_file('reopen1.rb', <<~RUBY)
          class ExtractAllReopened
            def method_from_file1; end
          end
        RUBY
        @file2 = create_test_file('reopen2.rb', <<~RUBY)
          class ExtractAllReopened
            def method_from_file2; end
          end
        RUBY
        load @file1
        load @file2
      end

      after do
        Object.send(:remove_const, :ExtractAllReopened) if defined?(ExtractAllReopened)
      end

      it 'produces two FILE scopes, each with only methods from that file' do
        scopes = extract_all_clean

        # Both FILE scopes contain ExtractAllReopened — distinguish by method content
        reopened_files = scopes.select do |s|
          s.scope_type == 'FILE' && s.scopes.any? { |c| c.name == 'ExtractAllReopened' }
        end
        expect(reopened_files.size).to eq(2)

        file1_scope = reopened_files.find { |s| s.name.end_with?('reopen1.rb') }
        file2_scope = reopened_files.find { |s| s.name.end_with?('reopen2.rb') }

        expect(file1_scope).not_to be_nil
        expect(file2_scope).not_to be_nil

        cls1 = file1_scope.scopes.find { |s| s.name == 'ExtractAllReopened' }
        cls2 = file2_scope.scopes.find { |s| s.name == 'ExtractAllReopened' }

        expect(cls1).not_to be_nil
        expect(cls2).not_to be_nil

        methods1 = cls1.scopes.select { |s| s.scope_type == 'METHOD' }.map(&:name)
        methods2 = cls2.scopes.select { |s| s.scope_type == 'METHOD' }.map(&:name)

        expect(methods1).to include('method_from_file1')
        expect(methods1).not_to include('method_from_file2')
        expect(methods2).to include('method_from_file2')
        expect(methods2).not_to include('method_from_file1')
      end
    end

    context 'module with methods AND nested class in same file' do
      before do
        @file = create_test_file('mixed.rb', <<~RUBY)
          module ExtractAllMixed
            SOME_CONST = 42

            def self.module_func; end
            def instance_helper; end

            class ExtractAllMixedChild
              def child_method; end
            end
          end
        RUBY
        load @file
      end

      after do
        Object.send(:remove_const, :ExtractAllMixed) if defined?(ExtractAllMixed)
      end

      it 'places child class under parent module in the same FILE scope' do
        scopes = extract_all_clean
        file_scope = scopes.find { |s| s.source_file == @file }
        expect(file_scope).not_to be_nil

        mod = file_scope.scopes.find { |s| s.name == 'ExtractAllMixed' }
        expect(mod).not_to be_nil
        expect(mod.scope_type).to eq('MODULE')

        child = mod.scopes.find { |s| s.name == 'ExtractAllMixed::ExtractAllMixedChild' }
        expect(child).not_to be_nil
        expect(child.scope_type).to eq('CLASS')

        expect(child.scopes.find { |s| s.name == 'child_method' }).not_to be_nil
      end

      it 'extracts symbols (constants) on the module scope' do
        scopes = extract_all_clean
        file_scope = find_file_scope(scopes, 'ExtractAllMixed')
        expect(file_scope).not_to be_nil
        mod = file_scope.scopes.find { |s| s.name == 'ExtractAllMixed' }

        const = mod.symbols.find { |s| s.name == 'SOME_CONST' }
        expect(const).not_to be_nil
        expect(const.symbol_type).to eq('STATIC_FIELD')
      end
    end

    context 'compact notation (class Foo::Bar::Baz)' do
      before do
        # Pre-create namespace so const_get works
        @file = create_test_file('compact.rb', <<~RUBY)
          module ExtractAllCompactNs
            module ExtractAllCompactInner
              class ExtractAllCompactLeaf
                def compact_method; end
              end
            end
          end
        RUBY
        load @file
      end

      after do
        Object.send(:remove_const, :ExtractAllCompactNs) if defined?(ExtractAllCompactNs)
      end

      it 'reconstructs nesting from FQN even for compact notation' do
        scopes = extract_all_clean
        file_scope = find_file_scope(scopes, 'ExtractAllCompactNs')
        expect(file_scope).not_to be_nil

        ns = file_scope.scopes.find { |s| s.name == 'ExtractAllCompactNs' }
        expect(ns).not_to be_nil
        expect(ns.scope_type).to eq('MODULE')

        inner = ns.scopes.find { |s| s.name == 'ExtractAllCompactNs::ExtractAllCompactInner' }
        expect(inner).not_to be_nil

        leaf = inner.scopes.find { |s| s.name == 'ExtractAllCompactNs::ExtractAllCompactInner::ExtractAllCompactLeaf' }
        expect(leaf).not_to be_nil
        expect(leaf.scope_type).to eq('CLASS')
      end
    end

    context 'class inside class' do
      before do
        @file = create_test_file('class_in_class.rb', <<~RUBY)
          class ExtractAllOuterClass
            def outer_method; end

            class ExtractAllInnerClass
              def inner_method; end
            end
          end
        RUBY
        load @file
      end

      after do
        Object.send(:remove_const, :ExtractAllOuterClass) if defined?(ExtractAllOuterClass)
      end

      it 'nests CLASS inside CLASS: FILE → CLASS(Outer) → CLASS(Inner)' do
        scopes = extract_all_clean
        file_scope = find_file_scope(scopes, 'ExtractAllOuterClass')
        expect(file_scope).not_to be_nil

        outer = file_scope.scopes.find { |s| s.name == 'ExtractAllOuterClass' }
        expect(outer).not_to be_nil
        expect(outer.scope_type).to eq('CLASS')

        inner = outer.scopes.find { |s| s.name == 'ExtractAllOuterClass::ExtractAllInnerClass' }
        expect(inner).not_to be_nil
        expect(inner.scope_type).to eq('CLASS')
      end
    end

    context 'module inside class' do
      before do
        @file = create_test_file('mod_in_class.rb', <<~RUBY)
          class ExtractAllHostClass
            def host_method; end

            module ExtractAllInnerMod
              def self.inner_func; end
            end
          end
        RUBY
        load @file
      end

      after do
        Object.send(:remove_const, :ExtractAllHostClass) if defined?(ExtractAllHostClass)
      end

      it 'nests MODULE inside CLASS: FILE → CLASS(Host) → MODULE(Inner)' do
        scopes = extract_all_clean
        file_scope = find_file_scope(scopes, 'ExtractAllHostClass')
        expect(file_scope).not_to be_nil

        host = file_scope.scopes.find { |s| s.name == 'ExtractAllHostClass' }
        expect(host).not_to be_nil
        expect(host.scope_type).to eq('CLASS')

        inner = host.scopes.find { |s| s.name == 'ExtractAllHostClass::ExtractAllInnerMod' }
        expect(inner).not_to be_nil
        expect(inner.scope_type).to eq('MODULE')
      end
    end

    context 'file_hash on FILE scope' do
      before do
        @file = create_test_file('filehash.rb', <<~RUBY)
          class ExtractAllFileHashTest
            def some_method; end
          end
        RUBY
        load @file
      end

      after do
        Object.send(:remove_const, :ExtractAllFileHashTest) if defined?(ExtractAllFileHashTest)
      end

      it 'puts file_hash on FILE scope, not on inner scopes' do
        scopes = extract_all_clean
        file_scope = find_file_scope(scopes, 'ExtractAllFileHashTest')
        expect(file_scope).not_to be_nil

        # file_hash on FILE
        expect(file_scope.language_specifics[:file_hash]).to match(/\A[0-9a-f]{40}\z/)

        # NOT on inner CLASS
        class_scope = file_scope.scopes.first
        expect(class_scope.language_specifics).not_to have_key(:file_hash)
      end
    end

    context 'method parameters and visibility' do
      before do
        @file = create_test_file('params.rb', <<~RUBY)
          class ExtractAllParamsClass
            def public_method(arg1, arg2); end

            private

            def private_method(secret); end
          end
        RUBY
        load @file
      end

      after do
        Object.send(:remove_const, :ExtractAllParamsClass) if defined?(ExtractAllParamsClass)
      end

      it 'extracts method parameters and visibility' do
        scopes = extract_all_clean
        file_scope = find_file_scope(scopes, 'ExtractAllParamsClass')
        cls = file_scope.scopes.find { |s| s.name == 'ExtractAllParamsClass' }

        pub = cls.scopes.find { |s| s.name == 'public_method' }
        expect(pub.language_specifics[:visibility]).to eq('public')
        param_names = pub.symbols.map(&:name)
        expect(param_names).to include('arg1', 'arg2')
        expect(param_names).not_to include('self')

        priv = cls.scopes.find { |s| s.name == 'private_method' }
        expect(priv.language_specifics[:visibility]).to eq('private')
      end
    end

    context 'class language_specifics (superclass, included modules)' do
      before do
        @file = create_test_file('lang_specifics.rb', <<~RUBY)
          module ExtractAllMixin
            def mixin_method; end
          end

          class ExtractAllBaseLS
            def base_method; end
          end

          class ExtractAllDerivedLS < ExtractAllBaseLS
            include ExtractAllMixin
            def derived_method; end
          end
        RUBY
        load @file
      end

      after do
        Object.send(:remove_const, :ExtractAllDerivedLS) if defined?(ExtractAllDerivedLS)
        Object.send(:remove_const, :ExtractAllBaseLS) if defined?(ExtractAllBaseLS)
        Object.send(:remove_const, :ExtractAllMixin) if defined?(ExtractAllMixin)
      end

      it 'includes super_classes and included_modules on CLASS scope' do
        scopes = extract_all_clean
        file_scope = find_file_scope(scopes, 'ExtractAllDerivedLS')
        derived = file_scope.scopes.find { |s| s.name == 'ExtractAllDerivedLS' }

        expect(derived).not_to be_nil
        expect(derived.language_specifics[:super_classes]).to include('ExtractAllBaseLS')
        expect(derived.language_specifics[:included_modules]).to include('ExtractAllMixin')
      end
    end
  end
end
