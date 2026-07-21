require 'bundler/audit/scanner'
require 'bundler/audit/database'

# Pure audit logic, extracted so it can be unit-tested without rake or a live
# network update. The rake task in dependency_audit.rake wires it to the real
# eligible lockfile set and the managed ignore list.
module DependencyAuditing
  module_function

  SEVERITIES = [:high, :critical].freeze

  Finding = Struct.new(:lockfile, :gem, :version, :criticality, :id)

  # Scan each lockfile with a single shared Database and return only the
  # findings whose criticality is in `severities`, excluding `ignore`.
  #
  # Returns an Array of Finding.
  def findings(lockfile_paths, database:, ignore:, severities: SEVERITIES)
    findings = []

    lockfile_paths.each do |lockfile_path|
      root = File.dirname(lockfile_path)
      name = File.basename(lockfile_path)
      scanner = Bundler::Audit::Scanner.new(root, name, database)

      scanner.scan(ignore: ignore) do |result|
        next unless result.respond_to?(:advisory)

        advisory = result.advisory
        next unless severities.include?(advisory.criticality)

        findings << Finding.new(
          lockfile_path,
          result.gem.name,
          result.gem.version.to_s,
          advisory.criticality,
          advisory.cve_id || advisory.ghsa_id || advisory.identifiers.first,
        )
      end
    end

    findings
  end

  # Load the managed ignore list from `.bundler-audit.yml` if present.
  # Format mirrors bundler-audit's own config: a top-level `ignore:` array.
  def load_ignore_list(config_path = '.bundler-audit.yml')
    return [] unless File.exist?(config_path)

    require 'yaml'
    config = YAML.safe_load(File.read(config_path)) || {}
    config['ignore'] || []
  end
end
