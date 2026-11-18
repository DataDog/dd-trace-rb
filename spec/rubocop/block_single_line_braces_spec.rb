# frozen_string_literal: true

require "spec_helper"

require "rubocop"
require "rubocop/rspec/support"
require "rubocop/vendor/standard-custom/lib/standard/cop/block_single_line_braces"

RSpec.describe RuboCop::Cop::Standard::BlockSingleLineBraces do
  subject(:cop) { described_class.new(config) }

  let(:config) { RuboCop::ConfigLoader.load_file(File.expand_path("../../.rubocop.yml", __dir__)) }

  it "corrects a single-line do/end block" do
    expect_offense(<<~RUBY)
      values.map do |value| value.to_s end
                 ^^ Prefer `{...}` over `do...end` for single-line blocks.
    RUBY

    expect_correction(<<~RUBY)
      values.map { |value| value.to_s }
    RUBY
  end

  it "accepts single-line braces" do
    expect_no_offenses("values.map { |value| value.to_s }")
  end

  it "accepts multiline do/end blocks" do
    expect_no_offenses(<<~RUBY)
      values.map do |value|
        value.to_s
      end
    RUBY
  end

  it "accepts multiline braces" do
    expect_no_offenses(<<~RUBY)
      values.map { |value|
        value.to_s
      }
    RUBY
  end

  it "accepts exception handling in a multiline block" do
    expect_no_offenses(<<~RUBY)
      values.map do |value|
        value.to_s
      rescue StandardError
        nil
      end
    RUBY
  end

  it "does not correct a block whose call has unparenthesised arguments" do
    expect_offense(<<~RUBY)
      consume value do |item| item.to_s end
                    ^^ Prefer `{...}` over `do...end` for single-line blocks.
    RUBY

    expect_no_corrections
  end
end
