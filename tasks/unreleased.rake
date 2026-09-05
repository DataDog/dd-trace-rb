# frozen_string_literal: true

require_relative "release_prep"

namespace :unreleased do
  desc "Validate unreleased/*.json changelog fragments (schema only; message hygiene is checked by unreleased:vale)"
  task :lint do
    ReleasePrep.validate_fragments!(ReleasePrep::Fragments.read_all)
    ReleasePrep::Fragments.read_examples
    puts "All unreleased/ changelog fragments are valid."
  rescue ReleasePrep::ValidationError => e
    ReleasePrep.fail!(e.message)
  end

  desc "Render the pending unreleased/ changelog fragments as they would appear in CHANGELOG.md"
  task :render do
    fragments = ReleasePrep::Fragments.read_all
    ReleasePrep.validate_fragments!(fragments)
    rendered = fragments.render
    puts rendered.empty? ? "(no pending changelog fragments)" : rendered
  rescue ReleasePrep::ValidationError => e
    ReleasePrep.fail!(e.message)
  end

  desc "Lint unreleased/ changelog fragment messages for hygiene with vale"
  task :vale do
    require "open3"

    fragments = ReleasePrep::Fragments.read_all
    ReleasePrep.validate_fragments!(fragments)
    next puts("No unreleased/ changelog fragments to lint.") if fragments.empty?

    # Vale's markdown parsing does not preserve trailing whitespace, so no vale rule
    # can detect it; checked here instead.
    offenders = fragments.select { |fragment| /[ \t]\z/.match?(fragment.message) }
    unless offenders.empty?
      ReleasePrep.fail!("Changelog message has trailing whitespace: #{offenders.map(&:path).join(", ")}")
    end

    # One vale invocation per fragment, message on stdin: no temp files, and
    # --ext makes vale parse stdin as markdown while --output=line keeps
    # each finding on one line so every finding becomes its own error
    # annotation. Exit status: 0 = clean, 1 = findings, anything else means
    # vale itself failed.
    config = File.expand_path(".vale.ini")
    findings = fragments.flat_map do |fragment|
      out, status = Open3.capture2("vale", "--config=#{config}", "--ext=.md", "--output=line", stdin_data: fragment.message)

      case status.exitstatus
      when 0
        []
      when 1
        out.split("\n").map { |finding| finding.sub("stdin.md:", "#{fragment.path}:") }
      else
        ReleasePrep.fail!("vale exited with #{status.exitstatus} for #{fragment.path}: #{out}")
      end
    end

    ReleasePrep.fail_all!(findings) unless findings.empty?
  rescue ReleasePrep::ValidationError => e
    ReleasePrep.fail!(e.message)
  end
end
