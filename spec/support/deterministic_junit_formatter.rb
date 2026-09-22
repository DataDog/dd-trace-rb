# JUnit formatter that replaces non-deterministic runtime values in test names
# (memory addresses, UUIDs, timestamps) with stable placeholders.
#
# Only affects JUnit XML output — example.metadata is never mutated,
# so other formatters (progress, documentation, etc.) see the original names.
#
# Usage in .rspec or via RSPEC_OPTS:
#   --require ./spec/support/deterministic_junit_formatter
#   --format DeterministicJunitFormatter
#   --out junit.xml

require "rspec_junit_formatter"

class DeterministicJunitFormatter < RspecJunitFormatter
  RSpec::Core::Formatters.register self, :start, :stop, :dump_summary

  class << self
    attr_writer :include_line_number
    attr_writer :metadata_properties

    def include_line_number
      @include_line_number || false
    end

    def metadata_properties
      @metadata_properties || []
    end
  end

  self.include_line_number = false
  self.metadata_properties = []

  SANITIZATIONS = [

    # Object with memory address: #<Foo::Bar:0x00007f... attrs> → #<Foo::Bar:0xXXXX>
    [/#<([A-Z][a-zA-Z_:]*):0x[0-9a-f]{6,}[^>]*>/, '#<\1:0xXXXX>'],
    # Proc or lambda: #<Proc:0x00007f... /path:line (lambda)> → #<Proc:0xXXXX>
    [/#<Proc:0x[0-9a-f]{6,}[^>]*>/, "#<Proc:0xXXXX>"],
    # UUID v4: 550e8400-e29b-41d4-a716-446655440000 → <UUID>
    [/\b[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b/i, "<UUID>"],
    # ISO 8601 timestamp: "2026-04-02 14:19:20.830733764 +0000" → <timestamp>
    [/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}[\d. +-]*/, "<timestamp>"],
    # Time.now.to_i → <time>
    [/\b\d{10}(\.\d+)?\b/, "<time>"],
    # hostname=>"15c5f63b0f37" → hostname=>"<hostname>"
    [/hostname=>"[0-9a-f]{12}"/, 'hostname=>"<hostname>"'],
    # "time_unix_nano" => 1779815589385879876 → time_unix_nano => <time_unix_nano>
    [/"time_unix_nano" ?=> ?\d{15,}/, "time_unix_nano => <time_unix_nano>"],

    # more agressive sanitizers, as many occurence does not have recognizable patterns
    [/0x[0-9a-f]{2,}/, "<hex>"],
    [/[0-9a-f]{16,}/, "<hex>"],  # 16 to not scrub short words with a-f only
    [/\d+\.\d+/, "<float>"],
    [/\d{4,}/, "<int>"],
  ]

  SCALAR_METADATA_CLASSES = [
    String,
    Symbol,
    Numeric,
    TrueClass,
    FalseClass,
    NilClass,
  ].freeze

  INVALID_ENCODING_REPLACEMENT = "\\uFFFD".freeze

  private

  def xml_dump
    output << %(<?xml version="1.0" encoding="UTF-8"?>\n)
    output << %(<testsuite)
    output << %( name="rspec#{escape(ENV["TEST_ENV_NUMBER"].to_s)}")
    output << %( tests="#{example_count}")
    output << %( skipped="#{pending_count}")
    output << %( failures="#{failure_count}")
    output << %( errors="#{error_count}")
    output << %( time="#{escape("%.6f" % duration)}")
    output << %( timestamp="#{escape(started.iso8601)}")
    output << %( hostname="#{escape(Socket.gethostname)}")
    output << %(>\n)
    xml_dump_properties
    xml_dump_examples
    output << %(</testsuite>\n)
  end

  def xml_dump_properties
    output << %(<properties>\n)
    suite_properties.each do |name, value|
      output << %(<property)
      output << %( name="#{escape(name)}")
      output << %( value="#{escape(value)}")
      output << %(/>\n)
    end
    output << %(</properties>\n)
  end

  def suite_properties
    [
      ["seed", RSpec.configuration.seed.to_s],
      ["rspec.version", RSpec::Core::Version::STRING],
    ]
  end

  def xml_dump_pending(notification)
    xml_dump_example(notification) do
      xml_dump_skipped(pending_message_for(notification))
    end
  end

  def xml_dump_skipped(message)
    if message && !message.empty?
      output << %(<skipped message="#{escape(message)}">)
      output << escape(message)
      output << %(</skipped>)
    else
      output << %(<skipped/>)
    end
  end

  def xml_dump_example(notification)
    output << %(<testcase)
    output << %( classname="#{escape(classname_for(notification))}")
    output << %( name="#{escape(description_for(notification))}")
    output << %( file="#{escape(example_group_file_path_for(notification))}")
    if self.class.include_line_number && (line_number = line_number_for(notification))
      output << %( line="#{escape(line_number)}")
    end
    if (duration = duration_for(notification))
      output << %( time="#{escape("%.6f" % duration)}")
    end
    output << %(>)
    yield if block_given?
    xml_dump_metadata_properties(notification)
    xml_dump_output(notification)
    output << %(</testcase>\n)
  end

  def xml_dump_metadata_properties(notification)
    properties = metadata_properties_for(notification)
    return if properties.empty?

    output << %(<properties>)
    properties.each do |name, value|
      output << %(<property)
      output << %( name="#{escape(name)}")
      output << %( value="#{escape(value)}")
      output << %(/>\n)
    end
    output << %(</properties>)
  end

  def metadata_properties_for(notification)
    metadata = notification.example.metadata
    Array(self.class.metadata_properties).each_with_object([]) do |key, properties|
      metadata_key = metadata_key_for(metadata, key)
      next unless metadata_key

      value = metadata[metadata_key]
      next unless scalar_metadata_value?(value)

      properties << [key.to_s, value.to_s]
    end
  end

  def metadata_key_for(metadata, key)
    return key if metadata.key?(key)

    symbol_key = key.to_sym if key.respond_to?(:to_sym)
    symbol_key if symbol_key && metadata.key?(symbol_key)
  end

  def scalar_metadata_value?(value)
    SCALAR_METADATA_CLASSES.any? { |klass| value.is_a?(klass) }
  end

  def line_number_for(notification)
    notification.example.metadata[:line_number]
  end

  def pending_message_for(notification)
    result = notification.example.execution_result
    result.pending_message if result.respond_to?(:pending_message)
  end

  def failure_for(notification)
    exception = exception_for(notification)
    if aggregate_failure_exception?(exception)
      strip_diff_colors(aggregate_failure_for(notification, exception))
    else
      super
    end
  end

  def aggregate_failure_exception?(exception)
    aggregate_failure_exceptions(exception).size > 1
  end

  def aggregate_failure_exceptions(exception)
    if exception.respond_to?(:all_exceptions)
      exception.all_exceptions
    elsif exception.respond_to?(:failures)
      exception.failures
    else
      []
    end
  end

  def aggregate_failure_for(notification, exception)
    lines = [exception.message]
    aggregate_failure_exceptions(exception).each_with_index do |subexception, index|
      lines << nil
      lines << "#{index + 1}) #{subexception.class}"
      lines << subexception.message
    end

    formatted_backtrace = notification.formatted_backtrace
    unless formatted_backtrace.empty?
      lines << nil
      lines.concat(formatted_backtrace)
    end

    lines.join("\n")
  end

  def escape(text)
    text.to_s.encode(
      Encoding::UTF_8,
      invalid: :replace,
      undef: :replace,
      replace: INVALID_ENCODING_REPLACEMENT
    ).gsub(ILLEGAL_REGEXP, ILLEGAL_REPLACEMENT).gsub(DISCOURAGED_REGEXP, DISCOURAGED_REPLACEMENTS)
  end

  def description_for(notification)
    sanitize(super)
  end

  def sanitize(str)
    SANITIZATIONS.reduce(str) { |value, (pattern, replacement)| value.gsub(pattern, replacement) }
  end
end
