# require "fileutils"
require "open3"
require "bundler"

lock_file_path = "./vendor/Gemfile.lock"
install_dir = "./vendor"

lock_file_parser = Bundler::LockfileParser.new(Bundler.read_file(lock_file_path))

gem_version_mapping = lock_file_parser.specs.each_with_object({}) do |spec, hash|
  hash[spec.name] = spec.version.to_s
  hash
end

def install_ddtrace_deps_without_native_extensions(gem_version_mapping: ,location: )
  [
    "debase-ruby_core_source",
    "libdatadog",
    "libddwaf"
  ].each do |gem|
    gem_install_cmd = "gem install #{gem} "\
    "--version #{gem_version_mapping[gem]} "\
    "--install-dir #{location} "\
    "--no-document "\
    "--ignore-dependencies "

    STDOUT.puts "Execute: #{gem_install_cmd}"
    output, status = Open3.capture2e(gem_install_cmd)
    STDOUT.puts output

    if status.success?
      next
    else
      break
    end
  end
end

def install_ddtrace_deps_with_native_extensions(gem_version_mapping: ,location: )
  [
    "msgpack",
    "ffi",
    "ddtrace"
  ].each do |gem|
    gem_install_cmd = "gem install #{gem} "\
      "--version #{gem_version_mapping[gem]} "\
      "--install-dir #{location} "\
      "--no-document "\
      "--ignore-dependencies "

    STDOUT.puts "Execute: #{gem_install_cmd}"
    output, status = Open3.capture2e(gem_install_cmd)
    STDOUT.puts output

    if status.success?
      next
    else
      break
    end
  end
end

if ENV["INSTALL_DDTRACE_NON_NATIVE_DEPS"] == 'true'
  install_ddtrace_deps_without_native_extensions(
    gem_version_mapping: gem_version_mapping,
    location: install_dir
  )
end

if ENV["INSTALL_DDTRACE_NATIVE_DEPS"] == 'true'
  install_ddtrace_deps_with_native_extensions(
    gem_version_mapping: gem_version_mapping,
    location: "#{install_dir}/#{RUBY_VERSION.split(".")[0..1].join(".")}"
  )
end
