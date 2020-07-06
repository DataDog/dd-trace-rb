module PlatformHelpers
  module_function

  def mri?
    RUBY_ENGINE == 'ruby'.freeze
  end

  def jruby?
    RUBY_ENGINE == 'jruby'.freeze || RUBY_ENGINE == 'truffleruby'
  end

  def supports_fork?
    !jruby?
  end
end
