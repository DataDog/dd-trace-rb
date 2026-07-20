#!/usr/bin/env ruby
# frozen_string_literal: true

# One-off remediation for a single Ruby version's slice of the
# dependency:audit backlog. See
# docs/superpowers/specs/2026-07-20-audit-backlog-remediation-design.md
# for the full design and rationale (never touches .bundler-audit.yml or
# Appraisals; staged lockfile changes are a human-reviewed candidate, not
# a commit). Usage: ruby tasks/remediate_audit_backlog.rb RUBY_VERSION
# (e.g. `ruby tasks/remediate_audit_backlog.rb 3.4`), run once per Ruby
# version inside that version's container.

require_relative 'dependency_audit'
require_relative 'audit_remediation/relock_lockfile'
require 'bundler/audit/database'
require 'fileutils'

RUBY_VERSION_ARG = ARGV[0] or abort 'Usage: ruby tasks/remediate_audit_backlog.rb RUBY_VERSION (e.g. 3.4)'
REPORT_PATH = File.expand_path("../docs/superpowers/reports/2026-07-20-audit-remediation-ruby#{RUBY_VERSION_ARG}.md", __dir__)
LOCKFILE_GLOBS = ["gemfiles/ruby_#{RUBY_VERSION_ARG}*.gemfile.lock", "gemfiles/ruby-#{RUBY_VERSION_ARG}*.gemfile.lock"].freeze

def find_target_lockfiles(database, ignore)
  lockfiles = LOCKFILE_GLOBS.flat_map { |pattern| Dir.glob(pattern) }.sort.uniq
  findings = DependencyAudit.high_critical_findings(lockfiles, database: database, ignore: ignore)

  findings.group_by { |f| f[:lockfile] }.transform_values { |fs| fs.map { |f| f[:gem] }.uniq }
end

def write_report(unresolved_entries)
  FileUtils.mkdir_p(File.dirname(REPORT_PATH))

  File.open(REPORT_PATH, 'w') do |f|
    f.puts "# Audit remediation report — Ruby #{RUBY_VERSION_ARG} (2026-07-20)"
    f.puts
    if unresolved_entries.empty?
      f.puts 'All targeted lockfiles resolved cleanly. Nothing to report.'
    else
      f.puts '| Lockfile | Gems attempted | Status | Details |'
      f.puts '|---|---|---|---|'
      unresolved_entries.each do |entry|
        detail =
          if entry[:status] == RelockLockfile::ERROR
            "bundler error: #{entry[:error_message]}"
          else
            entry[:remaining_findings].map { |rf| "#{rf[:gem]} #{rf[:version]} (#{rf[:id]})" }.join('; ')
          end
        f.puts "| #{entry[:lockfile]} | #{entry[:gems].join(', ')} | #{entry[:status]} | #{detail} |"
      end
    end
  end
end

def main
  puts 'Updating advisory database...'
  Bundler::Audit::Database.update!(quiet: true)
  database = Bundler::Audit::Database.new
  ignore = DependencyAudit.load_ignore_list

  targets = find_target_lockfiles(database, ignore)
  puts "Found #{targets.size} lockfile(s) with high/critical findings."

  resolved = []
  unresolved = []

  targets.each do |lockfile, gems|
    puts "Attempting relock: #{lockfile} (#{gems.join(', ')})"
    result = RelockLockfile.attempt(lockfile, gems, database: database, ignore: ignore)

    if result[:status] == RelockLockfile::RESOLVED
      resolved << lockfile
      puts "  resolved (stage manually): #{lockfile}"
    else
      unresolved << result.merge(gems: gems)
      puts "  #{result[:status]}"
    end
  end

  write_report(unresolved)

  puts
  puts "Summary: #{targets.size} attempted, #{resolved.size} resolved, #{unresolved.size} reported unresolvable."
  puts "Report written to #{REPORT_PATH}" unless unresolved.empty?
end

main if __FILE__ == $0
