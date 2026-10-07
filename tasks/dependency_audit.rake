require_relative "lockfile"

# The audit task runs standalone (gem-installed bundler-audit, `rake -f`),
# not as part of the bundle, so skip defining it entirely when the gem is
# absent -- e.g. under `bundle exec`, where requiring it would break every
# other rake task.
if Gem::Specification.find_all_by_name("bundler-audit").any?
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
        require "thor/shell"

        output_path = "tmp/dependency_audit_findings.json"
        FileUtils.mkdir_p(File.dirname(output_path))
        File.write(output_path, JSON.pretty_generate(findings.map(&:to_h)))

        puts
        puts "Dependency audit failed: #{findings.size} high/critical advisory match(es) " \
          "in #{findings.map(&:lockfile).uniq.size} lockfiles."
        puts
        puts "Fix or document them per docs/DependencyAudit.md " \
          "(details below, also written to #{output_path})."
        puts
        puts Thor::Shell::Basic.new.print_table(
          [%w[Lockfile Gem Version Advisory]] + findings.map { |f| [f.lockfile, f.gem, f.version, f.id] },
          {borders: true}
        )
        exit(1)
      end
    end
  end
end
