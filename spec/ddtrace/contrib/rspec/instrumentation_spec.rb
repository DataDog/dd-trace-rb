require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/ext/integration'

require 'rspec'
require 'ddtrace'

RSpec.describe 'RSpec hooks' do
  extend ConfigurationHelpers

  let(:configuration_options) { {} }

  around do |example|
    old_configuration = ::RSpec.configuration
    ::RSpec.configuration = ::RSpec::Core::Configuration.new

    Datadog.configure do |c|
      c.use :rspec, configuration_options
    end
    example.run

    RSpec.configuration = old_configuration
    Datadog.configuration.reset!
  end

  it 'creates span for example' do
    spans = []
    spec = RSpec.describe 'some test' do
      let(:active_span) { Datadog.configuration[:rspec][:tracer].active_span }

      it 'foo' do
        spans << active_span
      end
    end
    spec.run

    expect(spans.count).to eq(1)
    span = spans.first
    expect(span.span_type).to eq(Datadog::Ext::AppTypes::TEST)
    expect(span.name).to eq(Datadog::Contrib::RSpec::Ext::OPERATION_NAME)
    expect(span.resource).to eq('some test foo')
    expect(span.get_tag(Datadog::Ext::Test::TAG_NAME)).to eq('some test foo')
    expect(span.get_tag(Datadog::Ext::Test::TAG_SUITE)).to eq(spec.file_path)
    expect(span.get_tag(Datadog::Ext::Test::TAG_SPAN_KIND)).to eq(Datadog::Ext::AppTypes::TEST)
    expect(span.get_tag(Datadog::Ext::Test::TAG_TYPE)).to eq(Datadog::Contrib::RSpec::Ext::TEST_TYPE)
    expect(span.get_tag(Datadog::Ext::Test::TAG_FRAMEWORK)).to eq(Datadog::Contrib::RSpec::Ext::FRAMEWORK)
    expect(span.get_tag(Datadog::Ext::Test::TAG_STATUS)).to eq(Datadog::Ext::Test::Status::PASS)
  end

  it 'creates spans for several examples' do
    spans = []
    num_examples = 20
    spec = RSpec.describe 'many tests' do
      let(:active_span) { Datadog.configuration[:rspec][:tracer].active_span }

      num_examples.times do |n|
        it n do
          spans << active_span
        end
      end
    end
    spec.run

    expect(spans.count).to eq(num_examples)
  end

  it 'creates span for unnamed examples' do
    spans = []
    spec = RSpec.describe 'some unnamed test' do
      let(:active_span) { Datadog.configuration[:rspec][:tracer].active_span }

      it { spans << active_span }
    end
    spec.run

    expect(spans.count).to eq(1)
    span = spans.first
    expect(span.get_tag(Datadog::Ext::Test::TAG_NAME)).to match(/some unnamed test example at .+/)
  end

  it 'creates span for deeply nested examples' do
    spans = []
    spec = RSpec.describe 'some nested test' do
      let(:active_span) { Datadog.configuration[:rspec][:tracer].active_span }

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
                          it 'foo' do
                            spans << active_span
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
      end
    end
    spec.run

    expect(spans.count).to eq(1)
    span = spans.first
    expect(span.resource).to eq('some nested test 1 2 3 4 5 6 7 8 9 10 foo')
    expect(span.get_tag(Datadog::Ext::Test::TAG_NAME)).to eq('some nested test 1 2 3 4 5 6 7 8 9 10 foo')
    expect(span.get_tag(Datadog::Ext::Test::TAG_SUITE)).to eq(spec.file_path)
  end

  context 'catches failures' do
    def expect_failure
      expect(spans.count).to eq(1)
      span = spans.first
      expect(span.get_tag(Datadog::Ext::Test::TAG_STATUS)).to eq(Datadog::Ext::Test::Status::FAIL)
      expect(span).to have_error
      expect(span).to have_error_type
      expect(span).to have_error_message
      expect(span).to have_error_stack
    end

    it 'within let' do
      spans = []
      spec = RSpec.describe 'some failed test with let' do
        let(:active_span) { Datadog.configuration[:rspec][:tracer].active_span }
        let(:let_failure) { raise 'failure' }

        it 'foo' do
          spans << active_span
          let_failure
        end
      end
      spec.run

      expect_failure
    end

    it 'within around' do
      spans = []
      spec = RSpec.describe 'some failed test with around' do
        let(:active_span) { Datadog.configuration[:rspec][:tracer].active_span }

        around do |example|
          example.run
          raise 'failure'
        end

        it 'foo' do
          spans << active_span
        end
      end
      spec.run

      expect_failure
    end

    it 'within before' do
      spans = []
      spec = RSpec.describe 'some failed test with before' do
        let(:active_span) { Datadog.configuration[:rspec][:tracer].active_span }

        before do
          spans << active_span
          raise 'failure'
        end

        it 'foo' do
        end
      end
      spec.run

      expect_failure
    end

    it 'within after' do
      spans = []
      spec = RSpec.describe 'some failed test with before' do
        let(:active_span) { Datadog.configuration[:rspec][:tracer].active_span }

        after do
          raise 'failure'
        end

        it 'foo' do
          spans << active_span
        end
      end
      spec.run

      expect_failure
    end
  end
end
