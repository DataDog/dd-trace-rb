# frozen_string_literal: true

require 'datadog/symbol_database/extractor'
require 'fileutils'

RSpec.describe Datadog::SymbolDatabase::Extractor do
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
      expect(described_class.extract("not a module")).to be_nil
      expect(described_class.extract(42)).to be_nil
      expect(described_class.extract(nil)).to be_nil
    end

    it 'returns nil for anonymous module' do
      anonymous_mod = Module.new
      expect(described_class.extract(anonymous_mod)).to be_nil
    end

    it 'returns nil for anonymous class' do
      anonymous_class = Class.new
      expect(described_class.extract(anonymous_class)).to be_nil
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
        expect(described_class.extract(RSpec)).to be_nil
      end
    end

    context 'with stdlib code' do
      it 'returns nil for File class (stdlib)' do
        expect(described_class.extract(File)).to be_nil
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

      it 'extracts MODULE scope for user code module' do
        scope = described_class.extract(TestUserModule)

        expect(scope).not_to be_nil
        expect(scope.scope_type).to eq('MODULE')
        expect(scope.name).to eq('TestUserModule')
        expect(scope.source_file).to eq(@filename)
      end

      it 'includes file hash in language_specifics' do
        scope = described_class.extract(TestUserModule)

        expect(scope.language_specifics).to have_key(:file_hash)
        expect(scope.language_specifics[:file_hash]).to be_a(String)
        expect(scope.language_specifics[:file_hash].length).to eq(40)
      end

      it 'extracts module-level constants' do
        scope = described_class.extract(TestUserModule)

        constant_symbol = scope.symbols.find { |s| s.name == 'SOME_CONSTANT' }
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

      # INTERIM: top-level classes wrapped in PACKAGE (not MODULE) until
      # debugger-backend#1976 adds CLASS to ROOT_SCOPES. PACKAGE avoids
      # conflicting with Ruby's actual `module` keyword.
      it 'wraps top-level CLASS in a PACKAGE scope (interim until backend#1976)' do
        module_scope = described_class.extract(TestUserClass)

        expect(module_scope).not_to be_nil
        expect(module_scope.scope_type).to eq('PACKAGE')
        expect(module_scope.name).to eq('TestUserClass')
        expect(module_scope.source_file).to eq(@filename)
        expect(module_scope.scopes.size).to eq(1)

        class_scope = module_scope.scopes.first
        expect(class_scope.scope_type).to eq('CLASS')
        expect(class_scope.name).to eq('TestUserClass')
        expect(class_scope.source_file).to eq(@filename)
      end

      it 'extracts class variables' do
        class_scope = described_class.extract(TestUserClass).scopes.first

        class_var = class_scope.symbols.find { |s| s.name == '@@class_var' }
        expect(class_var).not_to be_nil
        expect(class_var.symbol_type).to eq('STATIC_FIELD')
      end

      it 'extracts constants' do
        class_scope = described_class.extract(TestUserClass).scopes.first

        constant = class_scope.symbols.find { |s| s.name == 'CONSTANT' }
        expect(constant).not_to be_nil
        expect(constant.symbol_type).to eq('STATIC_FIELD')
      end

      it 'extracts instance methods as METHOD scopes' do
        class_scope = described_class.extract(TestUserClass).scopes.first

        method_scopes = class_scope.scopes.select { |s| s.scope_type == 'METHOD' }
        method_names = method_scopes.map(&:name)

        expect(method_names).to include('public_method')
        expect(method_names).to include('private_method')
      end

      it 'does not extract class methods by default' do
        # Class methods are gated behind upload_class_methods: false because Ruby DI
        # instruments via prepend on the class (instance method chain), not the singleton class.
        class_scope = described_class.extract(TestUserClass).scopes.first

        class_method = class_scope.scopes.find { |s| s.name == 'self.class_method' }
        expect(class_method).to be_nil
      end

      it 'captures method visibility' do
        class_scope = described_class.extract(TestUserClass).scopes.first

        public_method = class_scope.scopes.find { |s| s.name == 'public_method' }
        expect(public_method.language_specifics[:visibility]).to eq('public')

        private_method = class_scope.scopes.find { |s| s.name == 'private_method' }
        expect(private_method.language_specifics[:visibility]).to eq('private')
      end

      it 'emits self as first ARG for instance methods' do
        class_scope = described_class.extract(TestUserClass).scopes.first
        method_scope = class_scope.scopes.find { |s| s.name == 'public_method' }

        expect(method_scope.symbols.first.name).to eq('self')
        expect(method_scope.symbols.first.symbol_type).to eq('ARG')
      end

      it 'does not emit self ARG for singleton methods' do
        # Class-method receiver is the class object, not an instance — `self` is
        # not a useful DI variable there, so extract_singleton_method_parameters
        # does not prepend a self ARG.
        method = TestUserClass.method(:class_method)
        symbols = described_class.send(:extract_singleton_method_parameters, method)
        expect(symbols.map(&:name)).not_to include('self')
      end

      it 'extracts method parameters' do
        class_scope = described_class.extract(TestUserClass).scopes.first
        method_scope = class_scope.scopes.find { |s| s.name == 'public_method' }

        arg1 = method_scope.symbols.find { |s| s.name == 'arg1' }
        expect(arg1).not_to be_nil
        expect(arg1.symbol_type).to eq('ARG')

        arg2 = method_scope.symbols.find { |s| s.name == 'arg2' }
        expect(arg2).not_to be_nil
        expect(arg2.symbol_type).to eq('ARG')
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

      it 'extracts namespaced class as its own root MODULE scope' do
        # TestNamespace::TestInnerClass is a user class and must be searchable.
        # Even though the parent TestNamespace has no methods (so it can't be extracted
        # itself), the class is extracted as a standalone PACKAGE-wrapped scope.
        scope = described_class.extract(TestNamespace::TestInnerClass)

        expect(scope).not_to be_nil
        expect(scope.scope_type).to eq('PACKAGE')
        expect(scope.name).to eq('TestNamespace::TestInnerClass')
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

      it 'also extracts the nested class as its own root MODULE scope' do
        # The nested class is extractable independently — it has a user code source file.
        # It also appears nested inside the parent MODULE, which is intentional:
        # mergeRootScopesWithSameName on the backend merges duplicates by name.
        scope = described_class.extract(TestNsModule::TestNsClass)

        expect(scope).not_to be_nil
        expect(scope.scope_type).to eq('PACKAGE')
        expect(scope.name).to eq('TestNsModule::TestNsClass')
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
        class_scope = described_class.extract(TestDerivedClass).scopes.first

        expect(class_scope.language_specifics[:super_classes]).to eq(['TestBaseClass'])
      end

      it 'excludes Object from super_classes' do
        class_scope = described_class.extract(TestBaseClass).scopes.first

        expect(class_scope.language_specifics).not_to have_key(:super_classes)
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
        class_scope = described_class.extract(TestClassWithMixin).scopes.first

        expect(class_scope.language_specifics[:included_modules]).to include('TestMixin')
      end
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
        expect(scope.name).to eq('TestA::TestB::TestC')
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
        extracted = ObjectSpace.each_object(Module).filter_map do |mod|
          name = Module.instance_method(:name).bind(mod).call rescue nil
          next unless name&.start_with?('TestA')
          described_class.extract(mod)
        end.compact

        if TestA.respond_to?(:const_source_location)
          expect(extracted.map(&:name)).to contain_exactly('TestA', 'TestA::TestB', 'TestA::TestB::TestC')
        else
          expect(extracted.map(&:name)).to eq(['TestA::TestB::TestC'])
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
      expect(described_class.send(:user_code_path?, '/path/to/gems/rspec/lib/rspec.rb')).to be false
    end

    it 'returns false for ruby stdlib paths' do
      expect(described_class.send(:user_code_path?, '/usr/lib/ruby/3.2/pathname.rb')).to be false
    end

    it 'returns false for internal paths' do
      expect(described_class.send(:user_code_path?, '<internal:array>')).to be false
    end

    it 'returns false for eval paths' do
      expect(described_class.send(:user_code_path?, '(eval):1')).to be false
    end

    it 'returns false for spec paths' do
      expect(described_class.send(:user_code_path?, '/project/spec/my_spec.rb')).to be false
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
      expect(described_class.send(:user_code_path?, '/app/lib/my_class.rb')).to be true
      expect(described_class.send(:user_code_path?, '/home/user/project/file.rb')).to be true
      expect(described_class.send(:user_code_path?, File.join(@test_dir, 'test.rb'))).to be true
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
      source_file = described_class.send(:find_source_file, TestClassForSourceFile)
      expect(source_file).to eq(@filename)
    end

    it 'returns nil for modules without methods' do
      empty_mod = Module.new

      source_file = described_class.send(:find_source_file, empty_mod)
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

      source_file = described_class.send(:find_source_file, TestClassWithMixedSources)
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

      source_file = described_class.send(:find_source_file, mod)
      expect(source_file).to eq(datadog_path)  # Falls back to first non-nil path
    end

    it 'falls back to gem path when no user code path exists' do
      gem_path = '/fake/gems/activerecord-7.0/lib/active_record/autosave.rb'
      mod = Module.new

      gem_method = instance_double(Method, source_location: [gem_path, 10])
      allow(mod).to receive(:instance_methods).with(false).and_return([:gem_method])
      allow(mod).to receive(:instance_method).with(:gem_method).and_return(gem_method)

      source_file = described_class.send(:find_source_file, mod)
      expect(source_file).to eq(gem_path)
    end
  end
end
