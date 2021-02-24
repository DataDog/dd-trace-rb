module PlatformHelpers
  module_function

  def mri?
    RUBY_ENGINE == 'ruby'.freeze
  end

  def jruby?
    RUBY_ENGINE == 'jruby'.freeze
  end

  def truffleruby?
    RUBY_ENGINE == 'truffleruby'.freeze
  end

  def supports_fork?
    !(jruby? || truffleruby?)
  end
end
