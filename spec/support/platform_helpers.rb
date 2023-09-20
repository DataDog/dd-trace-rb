require 'os'

module PlatformHelpers
  module_function

  # Ruby runtime engines

  def mri?
    'ruby'.freeze == RUBY_ENGINE
  end

  def jruby?
    'jruby'.freeze == RUBY_ENGINE
  end

  def truffleruby?
    'truffleruby'.freeze == RUBY_ENGINE
  end

  def engine_version
    version = defined?(RUBY_ENGINE_VERSION) ? RUBY_ENGINE_VERSION : RUBY_VERSION
    Gem::Version.new(version)
  end

  # Operating systems

  def linux?
    OS.linux?
  end

  def mac?
    OS.mac?
  end

  # Environment

  def ci?
    ENV.key?('CI')
  end

  # Feature support

  def supports_fork?
    Process.respond_to?(:fork)
  end
end
