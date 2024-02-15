require "open3"
require "rubygems"
require "bundler"
require "fileutils"
require "pathname"

ruby_api_version = Gem.ruby_api_version

current_path = Pathname.new(FileUtils.pwd)

tmp_path = current_path.join("tmp")

versioned_path = tmp_path.join(ruby_api_version)

FileUtils.mkdir_p(versioned_path, verbose: true)

gemfile_file_path = versioned_path.join('Gemfile')

File.open(gemfile_file_path, 'w') do |file|
  file.write("source \"https://rubygems.org\"\n")
  file.write("gem 'ddtrace', '#{ENV.fetch('RUBY_PACKAGE_VERSION')}', path: '#{current_path}'")
end

STDOUT.puts "Execute: bundle lock"
output, status = Open3.capture2e({ "BUNDLE_GEMFILE" => gemfile_file_path.to_s }, "bundle lock")
STDOUT.puts output

lock_file_path = versioned_path.join("Gemfile.lock")

lock_file_parser = Bundler::LockfileParser.new(Bundler.read_file(lock_file_path))

gem_version_mapping = lock_file_parser.specs.each_with_object({}) do |spec, hash|
  hash[spec.name] = spec.version.to_s
end

gem_version_mapping.each do |gem, version|
  env = {}

  gem_install_cmd = "gem install #{gem} "\
    "--version #{version} "\
    "--no-document "\
    "--ignore-dependencies "

  case gem
  when "ffi"
    gem_install_cmd << "--install-dir #{versioned_path} "
    # Install `ffi` gem with its built-in `libffi` native extension instead of using system's `libffi`
    gem_install_cmd << "-- --disable-system-libffi "
  when "ddtrace"
    # Install `ddtrace` gem locally without its profiling native extension
    env["DD_PROFILING_NO_EXTENSION"] = "true"
    gem_install_cmd =
      "gem install --local #{ENV.fetch('DDTRACE_GEM_LOCATION')} "\
      "--no-document "\
      "--ignore-dependencies "\
      "--install-dir #{versioned_path} "
  else
    gem_install_cmd << "--install-dir #{versioned_path} "
  end

  STDOUT.puts "Execute: #{gem_install_cmd}"
  output, status = Open3.capture2e(env, gem_install_cmd)
  STDOUT.puts output

  if status.success?
    next
  else
    exit 1
  end
end

FileUtils.cd(versioned_path.join("extensions/#{Gem::Platform.local.to_s}"), verbose: true) do
  # Symlink those directories to be utilized by Ruby compiled with shared libraries
  FileUtils.ln_sf Gem.extension_api_version, ruby_api_version
end
