module SpanHelpers
  RSpec::Matchers.define :have_error do
    match do |span|
      @actual = span.status
      values_match? Datadog::Ext::Errors::STATUS, @actual
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

  define_have_error_tag(:message, Datadog::Ext::Errors::MSG)
  define_have_error_tag(:stack, Datadog::Ext::Errors::STACK)
  define_have_error_tag(:type, Datadog::Ext::Errors::TYPE)

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
end
