source 'https://rubygems.org'

gemspec

# TODO: Use release gem when 'crack' releases version > 0.4.4, as we require
# TODO https://github.com/jnunemaker/crack/pull/62 for Ruby 3.0 to work.
if RUBY_VERSION >= '3.0.0'
  gem 'crack', git: 'https://github.com/jnunemaker/crack.git', ref: 'c61172bf32e1769748fded156c2f2fc03dac69c1'
  gem 'webrick', '>= 1.7.0' # No longer bundled by default since Ruby 3.0
end

# This file was generated by Appraisal
