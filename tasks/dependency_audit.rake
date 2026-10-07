require_relative "lockfile"

if Gem.loaded_specs.key?("bundler-audit")
  require_relative "dependency_auditing"

  namespace :dependency do
    desc "Audit eligible lockfiles for high/critical CVE advisories"
    task :audit do
      require "bundler/audit/database"

      puts "Updating advisory database..."
      begin
        updated = Bundler::Audit::Database.update!(quiet: true)
      rescue => e
        abort("Could not refresh the ruby-advisory-db (needs git + network): #{e.message}")
      end
      # `update!` returns `false` only when a `git pull`/download attempt
      # actually failed; it returns `nil` when the existing database isn't a
      # git checkout (nothing to pull, but the database is still usable), so
      # only `false` should be treated as a fatal error here.
      abort("Could not refresh the ruby-advisory-db (needs git + network)") if updated == false
      database = Bundler::Audit::Database.new

      lockfiles = Dir.glob("gemfiles/*.gemfile.lock").select { |path| Lockfile.new(path).audit_eligible? }.sort
      ignore = DependencyAuditing.load_ignore_list
      ignore_gem_versions = DependencyAuditing.load_ignore_gem_versions

      puts "Auditing #{lockfiles.size} lockfiles (high/critical only)..."
      findings = DependencyAuditing.findings(lockfiles, database: database, ignore: ignore, ignore_gem_versions: ignore_gem_versions)

      if findings.empty?
        puts "No high or critical advisories found."
      else
        # Column-aligned table for the job log, embedded in the single
        # GitHub Actions annotation (%0A = escaped newline).
        require "terminal-table"
        table_lines = Terminal::Table.new(
          headings: %w[Lockfile Gem Version Advisory],
          rows: findings.map { |f| [f.lockfile, f.gem, f.version, f.id] }
        ).to_s.lines.map(&:chomp)
        puts table_lines
        if ENV["GITHUB_ACTIONS"] == "true"
          doc_url = "#{ENV["GITHUB_SERVER_URL"]}/#{ENV["GITHUB_REPOSITORY"]}/blob/#{ENV["GITHUB_SHA"]}" \
            "/docs/DevelopmentGuide.md#dependency-audit-bundler-audit"
          puts "::error title=Dependency audit failed::#{findings.size} high/critical advisory match(es) " \
            "in #{findings.map(&:lockfile).uniq.size} lockfiles. " \
            "Fix or document the findings: #{doc_url}%0A#{table_lines.join("%0A")}"
        end
        abort("Dependency audit failed: #{findings.size} high/critical advisory match(es) listed above.")
      end
    end
  end
end
