require 'spec_helper'

RSpec.describe "SynchronizationHelpers#expect_in_fork" do
  it "works" do
    pid1 = Process.pid
    pid2 = nil
    expect_in_fork do
      pid2 = Process.pid
      expect(pid2).not_to eq(pid1)
    end
    expect(pid1).not_to eq(pid2)
  end

  it "errors for failing regular expectations" do
    expect {
      expect_in_fork do
        expect(1).to eq(2)
      end
    }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
  end

  it "errors for failing mock expectations" do
    expect {
      expect_in_fork do
        expect(Process).to receive(:pid)
        # Not calling Process.pid, should fail
      end
    }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
  end
end
