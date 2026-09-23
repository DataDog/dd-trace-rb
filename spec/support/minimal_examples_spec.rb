require "spec_helper"
require "support/minimal_examples"

RSpec.describe MinimalExamples do
  subject(:run_example) { sampler.run(example) }

  let(:sampler) { described_class.new }
  let(:example) { instance_double(RSpec::Core::Example::Procsy, metadata: {absolute_file_path: file_path}) }
  let(:file_path) { "/project/spec/example_spec.rb" }

  it "runs the first example from a file" do
    expect(example).to receive(:run)

    run_example
  end

  it "skips later examples from the same file" do
    first_example = instance_double(RSpec::Core::Example::Procsy, metadata: {absolute_file_path: file_path})
    allow(first_example).to receive(:run)
    sampler.run(first_example)
    expect(example).to receive(:skip)

    run_example
  end

  it "runs examples from different files" do
    first_example = instance_double(RSpec::Core::Example::Procsy, metadata: {absolute_file_path: "/project/spec/first_spec.rb"})
    allow(first_example).to receive(:run)
    sampler.run(first_example)
    expect(example).to receive(:run)

    run_example
  end
end
