# Runs alongside other formatters without affecting their output;
# each formatter only sees the notifications it registers for.
#
# Usage in .rspec or via RSPEC_OPTS:
#   --require ./spec/support/failures_only_formatter
#   --format FailuresOnlyFormatter
#   --out failures.txt

require "rspec/core/formatters/base_text_formatter"

class FailuresOnlyFormatter < RSpec::Core::Formatters::BaseTextFormatter
  RSpec::Core::Formatters.register self, :dump_failures, :dump_summary, :seed

  def message(_notification)
  end

  def dump_pending(_notification)
  end

  def dump_summary(summary)
    super
    @dumped_summary = true
  end

  # RSpec notifies :seed twice (once before the run starts, once after the
  # summary); only the second carries the seed actually used.
  def seed(notification)
    return unless @dumped_summary

    super
  end
end
