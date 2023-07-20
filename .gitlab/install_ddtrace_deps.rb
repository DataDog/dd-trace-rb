require "open3"
require "bundler"
require 'rbconfig'

lock_file_path = "./vendor/Gemfile.lock"
install_dir = "./vendor"

ruby_api_version = RbConfig::CONFIG["ruby_version"]

lock_file_parser = Bundler::LockfileParser.new(Bundler.read_file(lock_file_path))

gem_version_mapping = lock_file_parser.specs.each_with_object({}) do |spec, hash|
  if ARGV.include? spec.name
    hash[spec.name] = spec.version.to_s
  end

  hash
end

gem_version_mapping.each do |gem, version|
  env = {}

  gem_install_cmd = "gem install #{gem} "\
  "--version #{version} "\
  "--no-document "\
  "--ignore-dependencies "

  case gem
  when "ffi"
    gem_install_cmd << "--install-dir #{install_dir}/#{ruby_api_version} "
    gem_install_cmd << "-- --disable-system-libffi "
  when "ddtrace"
    env["DD_PROFILING_NO_EXTENSION"] = "true"
    gem_install_cmd << "--install-dir #{install_dir}/#{ruby_api_version} "
  when "msgpack"
    gem_install_cmd << "--install-dir #{install_dir}/#{ruby_api_version} "
  else
    gem_install_cmd << "--install-dir #{install_dir} "
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
