# frozen_string_literal: true

require 'os'

module PlatformHelpers
  module_function

  # Ruby runtime engines

  def mri?
    RUBY_ENGINE == 'ruby'
  end

  def jruby?
    RUBY_ENGINE == 'jruby'
  end

  def truffleruby?
    RUBY_ENGINE == 'truffleruby'
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
