# frozen_string_literal: true

require 'pathname'

# Default matchers are loaded immediately,
# so any new matcher we catch loading is ours.
require 'rspec/expectations'

module RakeMatchersHook
  class << self
    attr_reader :lines
  end
  @lines = []
  root_dir = Dir.pwd

  [:define, :define_negated_matcher, :alias_matcher].each do |name|
    define_method(name) do |matcher, *args, &block|
      location = caller_locations(1, 1).first.to_s # e.g. "bin.rb:4:in 'Kernel#load'"
      location.gsub!(/:in .*/, '') # Remove the `:in 'method'` suffix. e.g. "bin.rb:4"
      relative_location = Pathname.new(location).relative_path_from(root_dir).to_s

      RakeMatchersHook.lines << [relative_location, matcher.to_s]

      super(matcher, *args, &block)
    end
  end
end

RSpec::Matchers.singleton_class.prepend(RakeMatchersHook)

at_exit {
  puts RakeMatchersHook.lines.uniq(&:last).map { |m| m.join("\t") }
  $stdout.flush
  exit!(0)
}
