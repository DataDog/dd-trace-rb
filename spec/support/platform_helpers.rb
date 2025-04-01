# frozen_string_literal: true

require 'os'

module PlatformHelpers
  EQUALITY_OPERATOR = '=='
  ALLOWED_COMPARISON_OPERATORS = %w[> >= == != < <=].freeze

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

  def ruby_version_matches?(matcher_with_ruby_version)
    ruby_version = Gem::Version.new(RUBY_VERSION)
    operator, guard_version = matcher_with_ruby_version.split(' ', 2).tap { |array| array.unshift('==') if array.size == 1 }

    unless ALLOWED_COMPARISON_OPERATORS.include?(operator)
      message = "Unsupported operator: #{operator}. Supported operators: #{ALLOWED_COMPARISON_OPERATORS.join(', ')}"
      raise ArgumentError, message
    end

    unless Gem::Version.correct?(guard_version)
      message = "Invalid version: #{guard_version}. Make sure to add space between operator and version."
      raise ArgumentError, message
    end

    if operator == EQUALITY_OPERATOR && guard_version.count('.') < 3
      version = Gem::Version.new("#{guard_version}.0")
      (version...version.bump).cover?(ruby_version)
    else
      ruby_version.send(operator, Gem::Version.new(guard_version))
    end
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
