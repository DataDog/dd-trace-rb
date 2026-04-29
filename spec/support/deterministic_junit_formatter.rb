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

require 'rspec_junit_formatter'

class DeterministicJunitFormatter < RspecJunitFormatter
  RSpec::Core::Formatters.register self, :start, :stop, :dump_summary

  SANITIZATIONS = [
    # Object with memory address: #<Foo::Bar:0x00007f... attrs> → #<Foo::Bar:0xXXXX>
    [/#<([A-Z][a-zA-Z_:]*):0x[0-9a-f]{6,}[^>]*>/, '#<\1:0xXXXX>'],
    # Proc or lambda: #<Proc:0x00007f... /path:line (lambda)> → #<Proc:0xXXXX>
    [/#<Proc:0x[0-9a-f]{6,}[^>]*>/, '#<Proc:0xXXXX>'],
    # UUID v4: 550e8400-e29b-41d4-a716-446655440000 → <UUID>
    [/\b[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b/i, '<UUID>'],
    # ISO 8601 timestamp: "2026-04-02 14:19:20.830733764 +0000" → <timestamp>
    [/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}[\d. +-]*/, '<timestamp>'],
  ]

  private

  def description_for(notification)
    sanitize(super)
  end

  def sanitize(str)
    SANITIZATIONS.reduce(str) { |s, (pattern, replacement)| s.gsub(pattern, replacement) }
  end
end
