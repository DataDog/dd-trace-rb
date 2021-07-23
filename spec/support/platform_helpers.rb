require 'os'

module PlatformHelpers
  module_function

  # Ruby runtime engines

  def mri?
    RUBY_ENGINE == 'ruby'.freeze
  end

  def jruby?
    RUBY_ENGINE == 'jruby'.freeze
  end

  def truffleruby?
    RUBY_ENGINE == 'truffleruby'.freeze
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
end
