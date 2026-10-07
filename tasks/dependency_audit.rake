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
        # On GitHub Actions, also emit `::error` annotations so findings surface
        # on the lockfile that contains them, not just in the job log.
        in_ci = ENV["GITHUB_ACTIONS"] == "true"
        findings.each do |finding|
          severity = finding.criticality || "severity unknown"
          if in_ci
            puts "::error file=#{finding.lockfile},title=#{finding.gem} #{finding.version} #{finding.id}::" \
              "#{finding.id}: #{finding.gem} #{finding.version} (#{severity}) in #{finding.lockfile}"
          else
            puts "#{finding.lockfile}: #{finding.gem} #{finding.version} - #{finding.id} (#{severity})"
          end
        end
        abort("Dependency audit failed: #{findings.size} high/critical advisory match(es) listed above.")
      end
    end
  end
end
