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
        # One log line per finding; on GitHub Actions a single summary
        # annotation, because one annotation per finding floods the PR view.
        findings.each do |finding|
          severity = finding.criticality || "severity unknown"
          puts "#{finding.lockfile}: #{finding.gem} #{finding.version} - #{finding.id} (#{severity})"
        end
        if ENV["GITHUB_ACTIONS"] == "true"
          affected = findings.map { |f| "#{f.gem} #{f.version}" }.uniq.join(", ")
          doc_url = "#{ENV["GITHUB_SERVER_URL"]}/#{ENV["GITHUB_REPOSITORY"]}/blob/#{ENV["GITHUB_SHA"]}" \
            "/docs/DevelopmentGuide.md#dependency-audit-bundler-audit"
          puts "::error title=Dependency audit failed::#{findings.size} high/critical advisory match(es) in " \
            "#{findings.map(&:lockfile).uniq.size} lockfiles, affecting: #{affected}. " \
            "See the job log for the full list. Fix or document the findings: #{doc_url}"
        end
        abort("Dependency audit failed: #{findings.size} high/critical advisory match(es) listed above.")
      end
    end
  end
end
