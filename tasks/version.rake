namespace :version do
  task :bump do
    gemspec = Gem::Specification.load(Dir.glob('*.gemspec').first)

    gem_name = gemspec.name
    current_version = gemspec.version

    next_version =
      if current_version.prerelease?
        # If prerelease, return the release version (ie. 2.0.0.beta1 -> 2.0.0)
        current_version.release
      else
        # When releasing from `master` branch, return the next minor version (ie. 2.0.0 -> 2.1.0)
        major, minor, = current_version.segments
        Gem::Version.new([major, minor.succ, 0].join(".")).to_s
      end

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

    # Update the versions under gemfiles/
    sh "perl -p -i -e 's/\\b#{gem_name} \\(\\d+\\.\\d+\\.\\d+[^)]*\\)/#{gem_name} (#{next_version})/' gemfiles/*.lock"

    $stdout.puts next_version
  end

  def replace_version(find_pattern, replace_str)
    version_file = 'lib/datadog/version.rb'
    content = File.read(version_file)
    content.sub!(find_pattern, replace_str)
    File.write(version_file, content)
  end
end
