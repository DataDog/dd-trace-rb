# frozen_string_literal: true

require "spec_helper"

require "fileutils"
require "tmpdir"
require "rubocop"
require "rubocop/rspec/support"
require "rubocop/custom_cops/private_yard_type_cop"

RSpec.describe CustomCops::PrivateYardTypeCop do
  subject(:cop) { described_class.new }

  around do |example|
    Dir.mktmpdir("private_yard_type_cop") do |directory|
      Dir.chdir(directory) do
        FileUtils.mkdir_p(%w[lib sig])
        FileUtils.touch(source_path)
        example.run
      end
    end
  end

  let(:source_path) { File.expand_path("lib/example.rb") }
  let(:rbs_path) { File.expand_path("sig/example.rbs") }

  context "with a matching RBS file" do
    before { FileUtils.touch(rbs_path) }

    it "registers offenses for typed YARD tags on a private method" do
      expect_offense(<<~RUBY, source_path)
        class Example
          private

          # @param value [String]
          ^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/PrivateYardTypeCop: Private method's `@param`/`@return` type restates the RBS signature in `sig/example.rbs`. Remove the type annotation from prose; the `.rbs` file is the source of truth for non-public surfaces (see .agents/skills/write-comment/SKILL.md).
          # @return [Boolean]
          ^^^^^^^^^^^^^^^^^^^ CustomCops/PrivateYardTypeCop: Private method's `@param`/`@return` type restates the RBS signature in `sig/example.rbs`. Remove the type annotation from prose; the `.rbs` file is the source of truth for non-public surfaces (see .agents/skills/write-comment/SKILL.md).
          def valid?(value)
            !value.empty?
          end
        end
      RUBY
    end

    it "registers an offense for an inline private method" do
      expect_offense(<<~RUBY, source_path)
        class Example
          # @param [String] value
          ^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/PrivateYardTypeCop: Private method's `@param`/`@return` type restates the RBS signature in `sig/example.rbs`. Remove the type annotation from prose; the `.rbs` file is the source of truth for non-public surfaces (see .agents/skills/write-comment/SKILL.md).
          private def normalize(value)
            value.strip
          end
        end
      RUBY
    end

    it "does not register offenses for a public method" do
      expect_no_offenses(<<~RUBY, source_path)
        class Example
          public

          # @param value [String]
          # @return [Boolean]
          def valid?(value)
            !value.empty?
          end
        end
      RUBY
    end

    it "does not register offenses for a protected method" do
      expect_no_offenses(<<~RUBY, source_path)
        class Example
          protected

          # @param value [String]
          # @return [Boolean]
          def valid?(value)
            !value.empty?
          end
        end
      RUBY
    end

    it "does not register offenses for a public API" do
      expect_no_offenses(<<~RUBY, source_path)
        class Example
          private

          # @param value [String]
          # @return [Boolean]
          # @public_api
          def valid?(value)
            !value.empty?
          end
        end
      RUBY
    end

    it "does not register offenses for prose-only YARD tags" do
      expect_no_offenses(<<~RUBY, source_path)
        class Example
          private

          # @param value the value to validate
          # @return whether the value is valid
          def valid?(value)
            !value.empty?
          end
        end
      RUBY
    end

    it "does not register offenses for unrelated comments" do
      expect_no_offenses(<<~RUBY, source_path)
        class Example
          private

          # Normalization must happen before comparison.
          def valid?(value)
            !value.empty?
          end
        end
      RUBY
    end
  end

  context "without a matching RBS file" do
    it "does not register offenses for typed YARD tags on a private method" do
      expect_no_offenses(<<~RUBY, source_path)
        class Example
          private

          # @param value [String]
          # @return [Boolean]
          def valid?(value)
            !value.empty?
          end
        end
      RUBY
    end
  end
end
