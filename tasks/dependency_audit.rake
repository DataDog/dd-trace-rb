require_relative 'security_capabilities'

if Gem.loaded_specs.key?('bundler-audit')
  # standard:disable Lint/RequireRelativeSelfPath -- requires the DependencyAudit
  # module (dependency_audit.rb), not this .rake file; the cop matches on basename
  # only and treats the different extensions as a self-require.
  require_relative 'dependency_audit'
  # standard:enable Lint/RequireRelativeSelfPath

  namespace :dependency do
    desc 'Audit eligible lockfiles for high/critical CVE advisories'
    task :audit do
      require 'bundler/audit/database'

      puts 'Updating advisory database...'
      begin
        Bundler::Audit::Database.update!(quiet: true)
      rescue => e
        abort("Could not refresh the ruby-advisory-db (needs git + network): #{e.message}")
      end
      database = Bundler::Audit::Database.new

      lockfiles = SecurityCapabilities.audit_eligible_lockfiles
      ignore = DependencyAudit.load_ignore_list

      puts "Auditing #{lockfiles.size} lockfiles (high/critical only)..."
      findings = DependencyAudit.findings(lockfiles, database: database, ignore: ignore)

      if findings.empty?
        puts 'No high or critical advisories found.'
      else
        puts "Found #{findings.size} high/critical advisory match(es):"
        findings.each do |f|
          puts "  [#{f.criticality.to_s.upcase}] #{f.gem} #{f.version} #{f.id} (#{f.lockfile})"
        end
        abort('Dependency audit failed: high/critical advisories present.')
      end
    end
  end
end
