# frozen_string_literal: true

require 'pathname'

namespace :spec do
  # Task for discoverability of our RSpec conventions and tools.
  # DEV: We should really document our custom matchers.
  # DEV: Today, you have to figure out what they do by their name or inspecting their code.
  # DEV: A formal description would be nice.
  desc 'List custom RSpec matchers available in this codebase'
  task :custom_matchers do
    preload = "RUBYOPT='-r #{File.join(__dir__, "support", "custom_matchers_preload.rb")}'"

    # Load all spec files, print matchers, and exit.
    # Default `rspec/expectations` matcher are excluded.
    # Notes on execution:
    #   `ff`: clean output; `dry-run`: fast; `/dev/null`: the test target
    runtime_lines = `#{preload} bundle exec rspec -ff --dry-run  /dev/null`.lines.map(&:chomp)

    matchers = runtime_lines.map { |l| l.split("\t") }.to_h

    # Find all matchers that are not loaded by default, normally because
    # their are associated with specific gemsets (e.g. `be_hanami_rack_span`).
    # This list is more fuzzy, as it can't find dynamic matchers, or finds them
    # uninterpolated (e.g. `be_#{gem}_span`). The above runtime list is more accurate.
    grep = `grep -ERn 'RSpec::Matchers.(define|alias_matcher)' spec`.lines.map { |line|
      path, content = line.split(/(?<=\d):/, 2)
      [path, content[/(?<=[ \(]:)\S+/]]
    }

    # Merge lists, preferring runtime matchers over grep matchers
    grep.each do |path, matcher|
      matchers[path] = matcher unless matchers.key?(path)
    end

    # Print it nicely
    align_size = matchers.map { |_, matcher| matcher.size }.max
    puts "#{"Matcher".ljust(align_size)} Source"
    puts matchers.sort_by(&:last).map { |path, matcher| "#{matcher.ljust(align_size)} #{path}" }
  end
end
