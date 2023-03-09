require 'time'

require 'datadog/tracing'
require 'datadog/tracing/metadata/ext'

require 'datadog/ci/contrib/support/spec_helper'
require 'datadog/ci/contrib/rspec/integration'

RSpec.describe 'RSpec hooks' do
  include_context 'CI mode activated'

  before do
    Datadog.configure do |c|
      c.ci.instrument :rspec, service_name: 'lspec'
    end
  end

  # Yields to a block in a new RSpec global context. All RSpec
  # test configuration and execution should be wrapped in this method.
  def with_new_rspec_environment
    old_configuration = ::RSpec.configuration
    old_world = ::RSpec.world
    ::RSpec.configuration = ::RSpec::Core::Configuration.new
    ::RSpec.world = ::RSpec::Core::World.new

    yield
  ensure
    ::RSpec.configuration = old_configuration
    ::RSpec.world = old_world
  end

  it 'creates span for example' do
    spec = with_new_rspec_environment do
      RSpec.describe 'some test' do
        it 'foo' do; end
      end.tap(&:run)
    end

    expect(span.span_type).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST)
    expect(span.name).to eq(Datadog::CI::Contrib::RSpec::Ext::OPERATION_NAME)
    expect(span.resource).to eq('some test foo')
    expect(span.service).to eq('lspec')
    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_NAME)).to eq('some test foo')
    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_SUITE)).to eq(spec.file_path)
    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_SPAN_KIND)).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST)
    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_TYPE)).to eq(Datadog::CI::Contrib::RSpec::Ext::TEST_TYPE)
    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK)).to eq(Datadog::CI::Contrib::RSpec::Ext::FRAMEWORK)
    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK_VERSION)).to eq(
      Datadog::CI::Contrib::RSpec::Integration.version.to_s
    )
    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(Datadog::CI::Ext::Test::Status::PASS)
  end

  it 'creates correct span on shared examples' do
    spec = with_new_rspec_environment do
      require 'spec/datadog/ci/contrib/rspec/some_shared_examples'
      spec = RSpec.describe 'some test' do
        include_examples 'Testing shared examples'
      end.tap(&:run)
    end

    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_SUITE)).to eq(spec.file_path)
  end

  it 'creates spans for several examples' do
    num_examples = 20
    with_new_rspec_environment do
      RSpec.describe 'many tests' do
        num_examples.times do |n|
          it n do; end
        end
      end.run
    end

    expect(spans).to have(num_examples).items
  end

  it 'creates span for unnamed examples' do
    with_new_rspec_environment do
      RSpec.describe 'some unnamed test' do
        it do; end
      end.run
    end

    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_NAME)).to match(/some unnamed test example at .+/)
  end

  it 'creates span for deeply nested examples' do
    spec = with_new_rspec_environment do
      RSpec.describe 'some nested test' do
        context '1' do
          context '2' do
            context '3' do
              context '4' do
                context '5' do
                  context '6' do
                    context '7' do
                      context '8' do
                        context '9' do
                          context '10' do
                            it 'foo' do; end
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end.tap(&:run)
    end

    expect(span.resource).to eq('some nested test 1 2 3 4 5 6 7 8 9 10 foo')
    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_NAME)).to eq('some nested test 1 2 3 4 5 6 7 8 9 10 foo')
    expect(span.get_tag(Datadog::CI::Ext::Test::TAG_SUITE)).to eq(spec.file_path)
  end

  it 'creates spans for example with instrumentation' do
    with_new_rspec_environment do
      RSpec.describe 'some test' do
        it 'foo' do
          Datadog::Tracing.trace('get_time') do
            Time.now
          end
        end
      end.tap(&:run)
    end

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

    it 'within let' do
      with_new_rspec_environment do
        RSpec.describe 'some failed test with let' do
          let(:let_failure) { raise 'failure' }

          it 'foo' do
            let_failure
          end
        end.run
      end

      expect_failure
    end

    it 'within around' do
      with_new_rspec_environment do
        RSpec.describe 'some failed test with around' do
          around do |example|
            example.run
            raise 'failure'
          end

          it 'foo' do; end
        end.run
      end

      expect_failure
    end

    it 'within before' do
      with_new_rspec_environment do
        RSpec.describe 'some failed test with before' do
          before do
            raise 'failure'
          end

          it 'foo' do; end
        end.run
      end

      expect_failure
    end

    it 'within after' do
      with_new_rspec_environment do
        RSpec.describe 'some failed test with after' do
          after do
            raise 'failure'
          end

          it 'foo' do; end
        end.run
      end

      expect_failure
    end
  end
end
