require_relative 'security_capabilities'

if Gem.loaded_specs.key?('bundler-audit')
  require_relative 'dependency_auditing'

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
      ignore = DependencyAuditing.load_ignore_list

      puts "Auditing #{lockfiles.size} lockfiles (high/critical only)..."
      findings = DependencyAuditing.findings(lockfiles, database: database, ignore: ignore)

      if findings.empty?
        puts 'No high or critical advisories found.'
      else
        require 'json'
        require 'fileutils'

        output_path = 'tmp/dependency_audit_findings.json'
        FileUtils.mkdir_p(File.dirname(output_path))
        File.write(output_path, JSON.pretty_generate(findings.map(&:to_h)))

        puts "Found #{findings.size} high/critical advisory match(es); details written to #{output_path}"
        abort('Dependency audit failed: high/critical advisories present.')
      end
    end
  end
end
