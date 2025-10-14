# This module translates our custom mapping between appraisal and bundler.
module RuntimeMatcher
  def self.match?(rubies)
    ruby_version = RUBY_VERSION[0..2]

    if RUBY_PLATFORM == 'java'
      rubies.include?("✅ #{ruby_version}") && rubies.include?('✅ jruby')
    else
      rubies.include?("✅ #{ruby_version}")
    end
  end
end
