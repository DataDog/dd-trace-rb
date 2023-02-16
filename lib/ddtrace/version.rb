# typed: true

module DDTrace
  module VERSION
    MAJOR = 1
    MINOR = 9
    PATCH = 0
    PRE = nil

    STRING = [MAJOR, MINOR, PATCH, PRE].compact.join('.')

    MINIMUM_RUBY_VERSION = '2.1.0'.freeze

    # Restrict the installation of this gem version with untested future versions of Ruby.
    # But to allow testing with the next unreleased version of Ruby, this is set to the next Ruby version.
    MAXIMUM_RUBY_VERSION = '3.4'.freeze
  end
end
