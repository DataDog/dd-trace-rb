require "spec_helper"

require "fileutils"
require "open3"
require "rexml/document"
require "rexml/xpath"
require "pathname"
require "tmpdir"

require "spec/support/deterministic_junit_formatter"

RSpec.describe DeterministicJunitFormatter do
  subject(:junit_xml) { formatter_run.fetch(:xml) }

  let(:root) { File.expand_path("../..", __dir__) }
  let(:doc) { REXML::Document.new(junit_xml) }
  let(:testsuite) { xpath_first("/testsuite") }
  let(:testcases) { xpath_all("/testsuite/testcase") }
  let(:fixture_path) { formatter_run.fetch(:fixture_path) }

  let(:formatter_run) do
    tmp_root = File.join(root, "tmp")
    FileUtils.mkdir_p(tmp_root)

    Dir.mktmpdir("deterministic-junit-formatter-", tmp_root) do |dir|
      spec_path = File.join(dir, "formatter_fixture_spec.rb")
      configuration_path = File.join(dir, "formatter_configuration.rb")
      output_path = File.join(dir, "junit.xml")

      File.write(configuration_path, formatter_configuration)
      File.write(spec_path, formatter_fixture)

      stdout, stderr, status = Open3.capture3(
        {"SKIP_SIMPLECOV" => "1"},
        "bundle",
        "exec",
        "rspec",
        "--require",
        configuration_path,
        "--format",
        "progress",
        "--format",
        "DeterministicJunitFormatter",
        "--out",
        output_path,
        relative_path(spec_path),
        chdir: root
      )

      {
        fixture_path: relative_path(spec_path),
        xml: File.read(output_path),
        status: status,
        stdout: stdout,
        stderr: stderr,
      }
    end
  end

  def relative_path(path)
    Pathname.new(path).relative_path_from(Pathname.new(root)).to_s
  end

  def xpath_first(path, node = doc)
    REXML::XPath.first(node, path)
  end

  def xpath_all(path, node = doc)
    REXML::XPath.match(node, path)
  end

  def formatter_configuration
    <<~RUBY
      require './spec/support/deterministic_junit_formatter'

      DeterministicJunitFormatter.include_line_number = true
      DeterministicJunitFormatter.metadata_properties = [:junit_scalar, :junit_complex, :aggregate_failures]
    RUBY
  end

  def formatter_fixture
    <<~RUBY
      require 'stringio'

      RSpec.configure do |config|
        config.around(:each, :capture_output) do |example|
          original_stdout = $stdout
          original_stderr = $stderr
          stdout = StringIO.new
          stderr = StringIO.new

          $stdout = stdout
          $stderr = stderr
          example.run

          example.metadata[:stdout] = stdout.string
          example.metadata[:stderr] = stderr.string
        ensure
          $stdout = original_stdout
          $stderr = original_stderr
        end
      end

      RSpec.describe 'deterministic junit formatter fixture' do
        it 'passes with scalar metadata', junit_scalar: 'visible', junit_complex: ['hidden'] do
          expect(true).to be(true)
        end

        it 'skips with a reason' do
          skip 'not implemented yet'
        end

        it 'captures invalid bytes in output', :capture_output do
          $stdout.write([0xc3].pack('C').force_encoding(Encoding::UTF_8))
          $stderr.write([0xff].pack('C').force_encoding(Encoding::ASCII_8BIT))
        end

        it 'reports aggregate failure details', :aggregate_failures do
          expect('alpha').to eql('bravo')
          expect('charlie').to eql('delta')
        end
      end
    RUBY
  end

  it "emits strict JUnit XML with the formatter extensions used by dd-trace-rb", :aggregate_failures do
    expect(formatter_run.fetch(:status).exitstatus).to eq(1), formatter_run.values_at(:stdout, :stderr).join("\n")

    expect(testsuite["tests"]).to eq("4")
    expect(testsuite["failures"]).to eq("1")
    expect(testsuite["skipped"]).to eq("1")
    expect(xpath_first('/testsuite/properties/property[@name="rspec.version"]')["value"]).to eq(RSpec::Core::Version::STRING)

    expect(testcases.size).to eq(4)
    testcases.each do |testcase|
      expect(testcase["file"]).to eq("./#{fixture_path}")
      expect(testcase["line"]).to match(/\A\d+\z/)
    end

    skipped = xpath_first('//testcase[contains(@name, "skips with a reason")]/skipped')
    expect(skipped["message"]).to eq("not implemented yet")
    expect(skipped.text).to eq("not implemented yet")

    output_case = xpath_first('//testcase[contains(@name, "captures invalid bytes")]')
    expect(xpath_first("system-out", output_case).text).to eq('\\uFFFD')
    expect(xpath_first("system-err", output_case).text).to eq('\\uFFFD')

    metadata_case = xpath_first('//testcase[contains(@name, "passes with scalar metadata")]')
    expect(xpath_first('properties/property[@name="junit_scalar"]', metadata_case)["value"]).to eq("visible")
    expect(xpath_all('properties/property[@name="junit_complex"]', metadata_case)).to be_empty

    aggregate_case = xpath_first('//testcase[contains(@name, "reports aggregate failure details")]')
    expect(xpath_all("failure", aggregate_case).size).to eq(1)
    expect(xpath_first("failure", aggregate_case).text).to include('expected: "bravo"')
    expect(xpath_first("failure", aggregate_case).text).to include('expected: "delta"')
  end
end
