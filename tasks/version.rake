require 'open3'

namespace :version do
  task :next do
    current_version = load_gemspec_version

    next_version =
      if current_version.prerelease?
        # If prerelease, return the release version (ie. 2.0.0.beta1 -> 2.0.0)
        current_version.release
      else
        # When releasing from `master` branch, return the next minor version (ie. 2.0.0 -> 2.1.0)
        major, minor, = current_version.segments
        Gem::Version.new([major, minor.succ, 0].join(".")).to_s
      end

    $stdout.puts next_version
  end

  task :bump do |_t, args|
    input = args.extras.first || raise(ArgumentError, 'Please provide a version to bump')
    next_version = Gem::Version.new(input)

    major, minor, patch, pre = next_version.to_s.split(".")

    replace_version(/MAJOR = \d+/, "MAJOR = #{major}") if major
    replace_version(/MINOR = \d+/, "MINOR = #{minor}") if minor
    replace_version(/PATCH = \d+/, "PATCH = #{patch}") if patch
    # If we allows double quote string without interpolation in style => use "PRE = #{pre.inspect}" instead
    if pre
      replace_version(/PRE = \S+/, "PRE = '#{pre}'")
    else
      replace_version(/PRE = \S+/, "PRE = nil")
    end

    updated_version = load_gemspec_version

    raise "Version mismatch: #{updated_version} != #{next_version}" if updated_version != next_version

    gem_name = load_gemspec_name

    # Update the versions under gemfiles/
    sh "perl -p -i -e 's/\\b#{gem_name} \\(\\d+\\.\\d+\\.\\d+[^)]*\\)/#{gem_name} (#{next_version})/' gemfiles/*.lock"
  end

  # `Gem::Specification.load` has side effects
  # - it pollutes the global namespace with constants defined in the gemspec or its dependencies
  # - it populates @loaded_cache with the path of the loaded gemspec
  #
  # Causing stale constants or objects being retained in memory
  def load_gemspec_name(path = 'datadog.gemspec')
    stdout, _stderr, _status = Open3.capture3("ruby -e 'print Gem::Specification.load(\"#{path}\").name'")
    stdout
  end

  def load_gemspec_version(path = 'datadog.gemspec')
    stdout, _stderr, _status = Open3.capture3("ruby -e 'print Gem::Specification.load(\"#{path}\").version'")
    Gem::Version.new(stdout)
  end

  def replace_version(find_pattern, replace_str)
    version_file = 'lib/datadog/version.rb'
    content = File.read(version_file)
    content.sub!(find_pattern, replace_str)
    File.write(version_file, content)
  end
end
