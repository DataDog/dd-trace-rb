require_relative "lockfile"

begin
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
        require "json"
        require "fileutils"
        require "terminal-table"

        output_path = "tmp/dependency_audit_findings.json"
        FileUtils.mkdir_p(File.dirname(output_path))
        File.write(output_path, JSON.pretty_generate(findings.map(&:to_h)))

        puts "Dependency audit failed: #{findings.size} high/critical advisory match(es) " \
          "in #{findings.map(&:lockfile).uniq.size} lockfiles."
        puts "Fix or document them per docs/DevelopmentGuide.md#dependency-audit-bundler-audit " \
          "(details below, also written to #{output_path})."
        puts
        puts Terminal::Table.new(
          headings: %w[Lockfile Gem Version Advisory],
          rows: findings.map { |f| [f.lockfile, f.gem, f.version, f.id] }
        )
        exit(1)
      end
    end
  end
rescue LoadError
  # Define the task anyway so a missing gem install fails with instructions
  # instead of an unknown-task error.
  namespace :dependency do
    task :audit do
      abort("bundler-audit is not installed. Run: gem install bundler-audit, " \
        "then: rake -f tasks/dependency_audit.rake dependency:audit")
    end
  end
end
