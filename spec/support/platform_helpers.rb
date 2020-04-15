module PlatformHelpers
  module_function

  def mri?
    RUBY_ENGINE == 'ruby'.freeze
  end

  def jruby?
    RUBY_ENGINE == 'jruby'.freeze
  end

  def supports_fork?
    !jruby?
  end
end
