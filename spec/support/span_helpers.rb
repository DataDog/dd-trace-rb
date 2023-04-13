require 'datadog/tracing/metadata/ext'

module SpanHelpers
  RSpec::Matchers.define :have_error do
    match do |span|
      @actual = span.status
      values_match? Datadog::Tracing::Metadata::Ext::Errors::STATUS, @actual
    end

    def description_of(actual)
      "Span with status #{super}"
    end
  end

  def self.define_have_error_tag(tag_name, tag)
    RSpec::Matchers.define "have_error_#{tag_name}" do |*args|
      match do |span|
        expected = args.first

        @tag_name = tag_name
        @actual = span.get_tag(tag)

        if args.empty? && @actual
          # This condition enables the default matcher:
          # expect(foo).to have_error_tag
          return true
        end

        values_match? expected, @actual
      end

      match_when_negated do |span|
        expected = args.first

        @tag_name = tag_name
        @actual = span.get_tag(tag)

        if args.empty? && @actual.nil?
          # This condition enables the default matcher:
          # expect(foo).to_not have_error_tag
          return true
        end

        values_match? expected, @actual
      end

      def description_of(actual) # rubocop:disable Lint/NestedMethodDefinition
        "Span with error #{@tag_name} #{super}"
      end
    end
  end

  define_have_error_tag(:message, Datadog::Tracing::Metadata::Ext::Errors::TAG_MSG)
  define_have_error_tag(:stack, Datadog::Tracing::Metadata::Ext::Errors::TAG_STACK)
  define_have_error_tag(:type, Datadog::Tracing::Metadata::Ext::Errors::TAG_TYPE)

  # Distributed traces have the same trace_id and parent_id as upstream parent
  # span, but don't actually share the same Context with the parent.
  RSpec::Matchers.define :have_distributed_parent do |parent|
    match do |actual|
      @matcher = have_attributes(parent_id: parent.span_id, trace_id: parent.trace_id)
      @matcher.matches? actual
    end

    failure_message do
      @matcher.failure_message
    end
  end

  # Span with the metric '_dd.measured' set to 1.0.
  RSpec::Matchers.define :be_measured do
    match do |span|
      value = span.get_metric('_dd.measured')
      values_match? 1.0, value
    end

    def description_of(actual)
      "#{actual} with metrics #{actual.instance_variable_get(:@metrics)}"
    end
  end

  # Does this span have no parent span?
  RSpec::Matchers.define :be_root_span do
    match do |span|
      value = span.parent_id
      values_match? 0, value
    end
  end

  # @param tags [Hash] key value pairs to tags/metrics to assert on
  RSpec::Matchers.define :have_metadata do |tags|
    match do |actual|
      tags.all? do |key, value|
        values_match? value, actual.get_tag(key)
      end
    end

    match_when_negated do |actual|
      if tags.respond_to?(:any?)
        tags.any? do |key, value|
          !values_match? value, actual.get_tag(key)
        end
      else
        # Allows for `expect(span).to_not have_metadata('my.tag')` syntax
        values_match? nil, actual.get_tag(tags)
      end
    end

    def description_of(actual)
      "Span with metadata #{actual.send(:meta).merge(actual.send(:metrics))}"
    end
  end

  RSpec::Matchers.define :a_span_with do |expected|
    match do |actual|
      actual.instance_of?(Datadog::Tracing::Span) &&
        expected.all? do |key, value|
          actual.__send__(key) == value
        end
    end
  end

  RSpec::Matchers.define :a_span_operation_with do |expected|
    match do |actual|
      actual.instance_of?(Datadog::Tracing::SpanOperation) &&
        expected.all? do |key, value|
          actual.__send__(key) == value
        end
    end
  end
end
