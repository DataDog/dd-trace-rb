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
  # findings whose criticality is in `severities`, excluding `ignore` or
  # `ignore_gem_versions`.
  #
  # `ignore` matches bundler-audit's own semantics: a flat list of advisory
  # ids (CVE/GHSA), suppressed everywhere that id appears, regardless of gem
  # or version. `ignore_gem_versions` is scoped tighter -- each entry only
  # suppresses findings for that exact gem+version pair, so a fix that bumps
  # the gem (even to another still-vulnerable version) makes the finding
  # reappear instead of staying silently hidden.
  #
  # Returns an Array of Finding.
  def findings(lockfile_paths, database:, ignore:, severities: SEVERITIES, ignore_gem_versions: [])
    findings = []

    lockfile_paths.each do |lockfile_path|
      root = File.dirname(lockfile_path)
      name = File.basename(lockfile_path)
      scanner = Bundler::Audit::Scanner.new(root, name, database)

      scanner.scan(ignore: ignore) do |result|
        # scan also yields Results::InsecureSource (insecure gem source URLs),
        # which has no #advisory; only Results::UnpatchedGem is a CVE finding.
        next unless result.respond_to?(:advisory)

        advisory = result.advisory
        next unless severities.include?(advisory.criticality)

        gem_name = result.gem.name
        version = result.gem.version.to_s
        next if ignore_gem_versions.any? { |e| e['gem'] == gem_name && e['version'] == version }

        findings << Finding.new(
          lockfile_path,
          gem_name,
          version,
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
    load_config(config_path)['ignore'] || []
  end

  # Load the managed gem+version ignore list from `.bundler-audit.yml` if
  # present. Each entry is a Hash with 'gem' and 'version' keys (plus
  # documentation keys like 'reason' that callers don't need to read).
  def load_ignore_gem_versions(config_path = '.bundler-audit.yml')
    load_config(config_path)['ignore_gem_versions'] || []
  end

  def load_config(config_path)
    return {} unless File.exist?(config_path)

    require 'yaml'
    YAML.safe_load(File.read(config_path)) || {}
  end
end
