# frozen_string_literal: true

require "yaml"

# Guards the trailing `# Automated: Updated by ...` marker comments that
# .github/workflows/update-system-tests.yml depends on to keep the pinned
# system-tests ref in sync.
#
# Review history: a human PR (#6295, "feat(openfeature): activate delivery
# during provider initialization") temporarily replaced a pinned commit SHA
# with a branch name for local validation and, in doing so, silently dropped
# the trailing "# Automated: ..." comment on both affected lines. The marker
# is not cosmetic -- update-system-tests.yml's PATTERN regexes end in
# `(\s+# Automated:.*)`, so .github/scripts/update_reference.sh requires it
# to find and update the line. Without the marker, the script prints
# "No references found" and exits 0: the scheduled updater silently stops
# updating that reference instead of failing loudly. A reviewer caught this
# by actually running update_reference.sh against both versions of the file,
# and the author restored the markers before merging. That verification is
# mechanical -- it doesn't require any judgment about the surrounding
# change -- so it belongs in CI rather than in a human's attention budget.
#
# This script re-derives the (TARGET, PATTERN) pairs directly from
# update-system-tests.yml (the single source of truth for the updater) and
# fails if any pattern no longer matches its target file, i.e. if the
# "# Automated: ..." marker (or the rest of the pattern) has been removed,
# reworded, or otherwise broken.

WORKFLOW_PATH = ".github/workflows/update-system-tests.yml"
UPDATER_SCRIPT = ".github/scripts/update_reference.sh"

workflow = YAML.load_file(WORKFLOW_PATH)
steps = workflow.dig("jobs", "update-system-tests", "steps") || []

reference_steps = steps.select { |step| step["run"] == UPDATER_SCRIPT }

if reference_steps.empty?
  warn "::error::Expected to find at least one step in #{WORKFLOW_PATH} running #{UPDATER_SCRIPT}, found none. " \
       "Either the workflow was restructured (update this check to match) or the updater step was removed."
  exit 1
end

failures = []

reference_steps.each do |step|
  env = step["env"] || {}
  target = env["TARGET"]
  pattern = env["PATTERN"]

  if target.nil? || pattern.nil?
    failures << "A step running #{UPDATER_SCRIPT} in #{WORKFLOW_PATH} is missing TARGET and/or PATTERN env vars."
    next
  end

  unless File.exist?(target)
    failures << "#{WORKFLOW_PATH} references target file #{target.inspect}, which does not exist."
    next
  end

  # PATTERN is a Perl-compatible regex (consumed via `perl -pe` in
  # update_reference.sh), with capture groups used to splice in the new ref
  # while preserving everything else on the line -- including the trailing
  # "# Automated: ..." marker. Ruby's regex engine is close enough to Perl's
  # for this pattern shape (no lookaround, no named captures) to validate
  # that it still matches somewhere in the target file.
  regexp = Regexp.new(pattern)
  content = File.read(target)

  unless content.match?(regexp)
    failures << <<~MSG
      Pattern #{pattern.inspect} (from #{WORKFLOW_PATH}) no longer matches anything in #{target}.
      This usually means the trailing "# Automated: Updated by #{WORKFLOW_PATH}." marker comment (or
      the rest of the matched line) was edited or removed. That marker is required for
      #{UPDATER_SCRIPT} to find and update this reference -- without it, the scheduled updater
      silently no-ops (prints "No references found", exits 0) instead of keeping the pinned
      system-tests ref current.
      Restore the exact trailing comment (or, if this change is intentional, update both this file
      and the PATTERN in #{WORKFLOW_PATH} together).
    MSG
  end
end

if failures.any?
  failures.each { |message| warn "::error::#{message}" }
  exit 1
end

puts "All #{reference_steps.length} automated-reference marker(s) in #{WORKFLOW_PATH} are intact."