# frozen_string_literal: true

require "spec_helper"

require "rubocop"
require "rubocop/rspec/support"
require "rubocop/custom_cops/trailing_comma_in_arguments_cop"

RSpec.describe CustomCops::TrailingCommaInArgumentsCop do
  subject(:cop) { described_class.new(config) }

  let(:config) { RuboCop::ConfigLoader.load_file(File.expand_path("../../.rubocop.yml", __dir__)) }

  it "adds a comma after grouped keyword arguments" do
    expect_offense(<<~RUBY)
      Context.new(
        locals: locals,
        probe: probe, settings: settings, serializer: serializer
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Put a comma after the last parameter of a multiline method call.
      )
    RUBY

    expect_correction(<<~RUBY)
      Context.new(
        locals: locals,
        probe: probe, settings: settings, serializer: serializer,
      )
    RUBY
  end

  it "preserves a comma after grouped keyword arguments" do
    expect_no_offenses(<<~RUBY)
      Context.new(
        locals: locals,
        probe: probe, settings: settings, serializer: serializer,
      )
    RUBY
  end

  it "adds a comma after positional arguments grouped on one line" do
    expect_offense(<<~RUBY)
      call(
        first, second
               ^^^^^^ Put a comma after the last parameter of a multiline method call.
      )
    RUBY

    expect_correction(<<~RUBY)
      call(
        first, second,
      )
    RUBY
  end

  it "adds a comma when earlier positional arguments share a line" do
    expect_offense(<<~RUBY)
      call(
        first, second,
        third
        ^^^^^ Put a comma after the last parameter of a multiline method call.
      )
    RUBY

    expect_correction(<<~RUBY)
      call(
        first, second,
        third,
      )
    RUBY
  end

  it "adds a comma after a single multiline string argument" do
    expect_offense(<<~'RUBY')
      logger.warn(
        "Invalid scope. " \
        "Deactivating the feature."
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^ Put a comma after the last parameter of a multiline method call.
      )
    RUBY

    expect_correction(<<~'RUBY')
      logger.warn(
        "Invalid scope. " \
        "Deactivating the feature.",
      )
    RUBY
  end

  it "adds a comma before an inline comment" do
    expect_offense(<<~RUBY)
      call(
        first, fallback # Preserve the default.
               ^^^^^^^^ Put a comma after the last parameter of a multiline method call.
      )
    RUBY

    expect_correction(<<~RUBY)
      call(
        first, fallback, # Preserve the default.
      )
    RUBY
  end

  it "ignores comma characters inside a comment" do
    expect_no_offenses(<<~RUBY)
      call(
        first, second, # Keep these together, for readability.
      )
    RUBY
  end

  it "adds a comma to a safe-navigation call" do
    expect_offense(<<~RUBY)
      receiver&.call(
        first, second
               ^^^^^^ Put a comma after the last parameter of a multiline method call.
      )
    RUBY

    expect_correction(<<~RUBY)
      receiver&.call(
        first, second,
      )
    RUBY
  end

  it "adds a comma to an indexed call" do
    expect_offense(<<~RUBY)
      receiver[
        first, second
               ^^^^^^ Put a comma after the last parameter of a multiline method call.
      ]
    RUBY

    expect_correction(<<~RUBY)
      receiver[
        first, second,
      ]
    RUBY
  end

  it "removes a comma when the closing parenthesis shares the last argument's line" do
    expect_offense(<<~RUBY)
      call(
        first,
        second,)
              ^ Avoid comma after the last parameter of a method call, unless that item immediately precedes a newline.
    RUBY

    expect_correction(<<~RUBY)
      call(
        first,
        second)
    RUBY
  end

  it "removes a comma before a closing bracket on the same line" do
    expect_offense(<<~RUBY)
      receiver[
        first,
        second,]
              ^ Avoid comma after the last parameter of a method call, unless that item immediately precedes a newline.
    RUBY

    expect_correction(<<~RUBY)
      receiver[
        first,
        second]
    RUBY
  end

  it "removes a comma from a single-line call" do
    expect_offense(<<~RUBY)
      call(first, second,)
                        ^ Avoid comma after the last parameter of a method call, unless that item immediately precedes a newline.
    RUBY

    expect_correction(<<~RUBY)
      call(first, second)
    RUBY
  end

  it "does not add an argument comma after a nested array's closing bracket" do
    expect_no_offenses(<<~RUBY)
      call(first, [
        second,
      ])
    RUBY
  end

  it "does not add an argument comma when a single nested call shares the closing line" do
    expect_no_offenses(<<~RUBY)
      call(nested(
        first, second,
      ))
    RUBY
  end

  it "adds a comma after a heredoc opener" do
    expect_offense(<<~RUBY)
      call(
        <<~TEXT
        ^^^^^^^ Put a comma after the last parameter of a multiline method call.
          message
        TEXT
      )
    RUBY

    expect_correction(<<~RUBY)
      call(
        <<~TEXT,
          message
        TEXT
      )
    RUBY
  end

  it "does not add a comma after an explicit block argument" do
    expect_no_offenses(<<~RUBY)
      call(
        first, &block
      )
    RUBY
  end

  it "does not require parentheses or arguments" do
    expect_no_offenses(<<~RUBY)
      call first,
        second
      call
      call()
    RUBY
  end
end
