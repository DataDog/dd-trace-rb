# frozen_string_literal: true

require "rbconfig"
require "tmpdir"

namespace :test do
  desc "Test the Virel serializer; optionally validate with a Virel checkout"
  task :miteruby_virel, [:virel_checkout] => :compile do |_task, args|
    build_dir = "tmp/#{RUBY_PLATFORM}/datadog_profiling_native_extension.#{RUBY_VERSION}_#{RUBY_PLATFORM}/#{RUBY_VERSION}"
    ruby_libs = RbConfig::CONFIG.fetch((RbConfig::CONFIG["ENABLE_SHARED"] == "yes") ? "LIBRUBYARG_SHARED" : "LIBRUBYARG_STATIC")
    ruby_libs = "#{ruby_libs} #{RbConfig::CONFIG["MAINLIBS"]}"
    Dir.mktmpdir("miteruby-virel") do |directory|
      binary = File.join(directory, "serializer-test")
      fixture = File.join(directory, "samples.virl")
      sh "make", "-C", build_dir, "-f", "Makefile", "-f", File.expand_path("spec/datadog/profiling/miteruby_virel_serializer_test.mk"),
        "miteruby-virel-test", "TEST_RUBY_LIBS=#{ruby_libs}", "VIREL_TEST_BINARY=#{binary}"
      sh binary, fixture
      if args[:virel_checkout]
        sh "python3", "-B", "spec/datadog/profiling/validate_virel.py", args[:virel_checkout], fixture
      end
    end
  end
end
