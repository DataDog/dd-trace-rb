require 'bundler'
require 'json'
require 'set'

def parse_ddtrace_gemfiles(integrated_gems)
    # Find latest CRuby version
    cruby_paths = Dir['gemfiles/ruby_*.lock']

    # Group gemfiles by CRuby version, with latest CRuby version first
    gemfiles = cruby_paths.map { |p| [Gem::Version.new(p.match(/ruby_([^_]+)/)[1]), p] }
                          .sort_by { |p| p.first }.reverse
                          .chunk_while { |v1, v2| v1.first == v2.first }.map { |v| v.map(&:last) }

    # Get all gem versions in the gemlock files
    gems = {}
    gemfiles.each do |files|
      files.each do |file|

        parser = Bundler::LockfileParser.new(File.read(file))
        specs = parser.specs
        specs.each do |spec|
            (gems[spec.name] ||= Set[]).add(spec.version.to_s)
        end
      end

      if (gems.keys & integrated_gems).size == integrated_gems.size
        # If we didn't find all integrated gems, we should keep searching in older
        # Ruby versions. Otherwise we can stop here.
        break
      end
    end

    gems
end

ddtrace_specs = `grep -Rho 'Gem.loaded_specs.*' lib/datadog/tracing/contrib/`

integrated_gems = ddtrace_specs.split.map { |m| m.match(/Gem.loaded_specs\[.([^\]]+).\]/)&.[](1) }.uniq.compact

payload = {
  "data" => {
    "type" => "supported_integrations",
    "id" => "1",
    "attributes" => {
      "language_language" => "ruby",
      "tracer_version" => "add-version-here",
      "integrations" => []
    }
  }
}
tested_integrations = parse_ddtrace_gemfiles(integrated_gems)
integrated_gems.each do |integration|
    # puts integration + " " + tested_integrations[integration].to_s
    
    tested_integrations[integration].each do |v|
      payload["data"]["attributes"]["integrations"].append({
        "integration_name" => integration,
        "integration_version" => v,
        "dependency_name" => integration
      })
    end
end

# send API call to endpoint
puts JSON.generate(payload)
JSON.generate(payload)