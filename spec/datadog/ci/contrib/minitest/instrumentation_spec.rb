require 'time'

require 'datadog/tracing'
require 'datadog/tracing/metadata/ext'

require 'datadog/ci/contrib/support/spec_helper'
require 'datadog/ci/contrib/minitest/integration'

RSpec.describe 'Minitest hooks' do
  include_context 'CI mode activated'

  before do
    Datadog.configure do |c|
      c.ci.instrument :minitest, service_name: 'ltest'
    end
  end

  it 'creates span for test' do
    klass = Class.new(Minitest::Test) do
      def self.name
        'SomeTest'
      end

      def test_foo; end
    end

    klass.new(:test_foo).run

    expect(span.span_type).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST)
    expect(span.name).to eq(Datadog::CI::Contrib::Minitest::Ext::OPERATION_NAME)
    expect(span.resource).to eq('SomeTest#test_foo')
    expect(span.service).to eq('ltest')
    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_NAME)).to eq('SomeTest#test_foo')
    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_SUITE)).to eq(
      'spec/datadog/ci/contrib/minitest/instrumentation_spec.rb'
    )
    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_SPAN_KIND)).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST)
    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_TYPE)).to eq(Datadog::CI::Contrib::Minitest::Ext::TEST_TYPE)
    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK)).to eq(Datadog::CI::Contrib::Minitest::Ext::FRAMEWORK)
    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK_VERSION)).to eq(
      Datadog::CI::Contrib::Minitest::Integration.version.to_s
    )
    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(Datadog::CI::Ext::Test::Status::PASS)
  end

  it 'creates spans for several tests' do
    num_tests = 20

    klass = Class.new(Minitest::Test) do
      def self.name
        'SomeTest'
      end

      num_tests.times do |i|
        define_method("test_#{i}") { ; }
      end
    end

    num_tests.times do |i|
      klass.new("test_#{i}").run
    end

    expect(spans).to have(num_tests).items
  end

  it 'creates spans for example with instrumentation' do
    klass = Class.new(Minitest::Test) do
      def self.name
        'SomeTest'
      end

      def test_foo
        Datadog::Tracing.trace('get_time') do
          Time.now
        end
      end
    end

    klass.new(:test_foo).run

    expect(spans).to have(2).items

    spans.each do |span|
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::Distributed::TAG_ORIGIN))
        .to eq(Datadog::CI::Ext::Test::CONTEXT_ORIGIN)
    end
  end

  context 'catches failures' do
    def expect_failure
      expect(span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(Datadog::CI::Ext::Test::Status::FAIL)
      expect(span).to have_error
      expect(span).to have_error_type
      expect(span).to have_error_message
      expect(span).to have_error_stack
    end

    it 'within test' do
      klass = Class.new(Minitest::Test) do
        def self.name
          'SomeTest'
        end

        def test_foo
          assert false
        end
      end

      klass.new(:test_foo).run

      expect_failure
    end

    it 'within setup' do
      klass = Class.new(Minitest::Test) do
        def self.name
          'SomeTest'
        end

        def setup
          assert false
        end

        def test_foo; end
      end

      klass.new(:test_foo).run

      expect_failure
    end

    it 'within teardown' do
      klass = Class.new(Minitest::Test) do
        def self.name
          'SomeTest'
        end

        def teardown
          assert false
        end

        def test_foo; end
      end

      klass.new(:test_foo).run

      expect_failure
    end
  end

  context 'catches errors' do
    def expect_failure
      expect(span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(Datadog::CI::Ext::Test::Status::FAIL)
      expect(span).to have_error
      expect(span).to have_error_type
      expect(span).to have_error_message
      expect(span).to have_error_stack
    end

    it 'within test' do
      klass = Class.new(Minitest::Test) do
        def self.name
          'SomeTest'
        end

        def test_foo
          raise 'Error!'
        end
      end

      klass.new(:test_foo).run

      expect_failure
    end

    it 'within setup' do
      klass = Class.new(Minitest::Test) do
        def self.name
          'SomeTest'
        end

        def setup
          raise 'Error!'
        end

        def test_foo; end
      end

      klass.new(:test_foo).run

      expect_failure
    end

    it 'within teardown' do
      klass = Class.new(Minitest::Test) do
        def self.name
          'SomeTest'
        end

        def teardown
          raise 'Error!'
        end

        def test_foo; end
      end

      klass.new(:test_foo).run

      expect_failure
    end
  end

  context 'catches skips' do
    def expect_skip
      expect(span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(Datadog::CI::Ext::Test::Status::SKIP)
      expect(span).to_not have_error
    end

    it 'with reason' do
      klass = Class.new(Minitest::Test) do
        def self.name
          'SomeTest'
        end

        def test_foo
          skip 'Skip!'
        end
      end

      klass.new(:test_foo).run

      expect_skip
      expect(span.get_tag(Datadog::CI::Ext::Test::TAG_SKIP_REASON)).to eq('Skip!')
    end

    it 'without reason' do
      klass = Class.new(Minitest::Test) do
        def self.name
          'SomeTest'
        end

        def test_foo
          skip
        end
      end

      klass.new(:test_foo).run

      expect_skip
      expect(span.get_tag(Datadog::CI::Ext::Test::TAG_SKIP_REASON)).to eq('Skipped, no message given')
    end

    it 'within test' do
      klass = Class.new(Minitest::Test) do
        def self.name
          'SomeTest'
        end

        def test_foo
          skip 'Skip!'
        end
      end

      klass.new(:test_foo).run

      expect_skip
    end

    it 'within setup' do
      klass = Class.new(Minitest::Test) do
        def self.name
          'SomeTest'
        end

        def setup
          skip 'Skip!'
        end

        def test_foo; end
      end

      klass.new(:test_foo).run

      expect_skip
    end

    it 'within teardown' do
      klass = Class.new(Minitest::Test) do
        def self.name
          'SomeTest'
        end

        def teardown
          skip 'Skip!'
        end

        def test_foo; end
      end

      klass.new(:test_foo).run

      expect_skip
    end
  end
end
