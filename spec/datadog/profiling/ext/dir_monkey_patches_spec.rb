require "datadog/profiling/spec_helper"

require "datadog/profiling/collectors/cpu_and_wall_time_worker"
require "datadog/profiling/ext/dir_monkey_patches"

# NOTE: Specs in this file are written so as to not leave the DirMonkeyPatches loaded into the Ruby VM after this
# test executes. They do this by only applying these monkey patches in a separate process.
RSpec.describe Datadog::Profiling::Ext::DirMonkeyPatches do
  before do
    skip_if_profiling_not_supported(self)

    File.write("#{temporary_directory}/file1", "file1")
    File.write("#{temporary_directory}/file2", "file2")
    File.write("#{temporary_directory}/file3", "file3")

    expect(Datadog::Profiling::Collectors::CpuAndWallTimeWorker).to_not receive(:_native_hold_signals)
    expect(Datadog::Profiling::Collectors::CpuAndWallTimeWorker).to_not receive(:_native_resume_signals)
  end

  let(:temporary_directory) { Dir.mktmpdir }
  let(:temporary_files_count) { 3 }
  let(:expected_hold_resume_calls_count) { 1 }

  after do
    FileUtils.remove_dir(temporary_directory)
  rescue Errno::ENOENT => _e
    # Do nothing, it's ok
  end

  describe "DirClassMonkeyPatches" do
    describe ".[]" do
      it "matches the ruby behavior without monkey patching" do
        test_with_and_without_monkey_patch do
          expect(Dir["*1", "*2", base: temporary_directory]).to contain_exactly("file1", "file2")
        end
      end
    end

    describe ".children" do
      it "matches the ruby behavior without monkey patching" do
        test_with_and_without_monkey_patch do
          result = Dir.children(temporary_directory, encoding: "US-ASCII").sort
          expect(result.first.encoding).to be Encoding::US_ASCII
          expect(result.first).to eq "file1"
        end
      end
    end

    describe ".each_child" do
      let(:expected_hold_resume_calls_count) { 1 + temporary_files_count }

      context "with a block" do
        it "matches the ruby behavior without monkey patching" do
          test_with_and_without_monkey_patch do
            files = []

            Dir.each_child(temporary_directory, encoding: "UTF-8") { |it| files << it }

            expect(files).to contain_exactly("file1", "file2", "file3")
          end
        end

        it "allows signals to arrive inside the user block" do
          test_with_monkey_patch do
            ran_assertion = false

            Dir.each_child(temporary_directory, encoding: "UTF-8") do
              expect_sigprof_to_be(:unblocked)
              ran_assertion = true
            end

            expect(ran_assertion).to be true
          end
        end
      end

      context "without a block" do
        it "matches the ruby behavior without monkey patching" do
          test_with_and_without_monkey_patch do
            expect(Dir.each_child(temporary_directory, encoding: "UTF-8").to_a).to include("file1", "file2", "file3")
          end
        end
      end
    end

    describe ".empty?" do
      it "matches the ruby behavior without monkey patching" do
        test_with_and_without_monkey_patch do
          expect(Dir.empty?(temporary_directory)).to be false
        end
      end
    end

    describe ".entries" do
      it "matches the ruby behavior without monkey patching" do
        test_with_and_without_monkey_patch do
          expect(Dir.entries(temporary_directory)).to contain_exactly(".", "..", "file1", "file2", "file3")
        end
      end
    end

    describe ".foreach" do
      let(:expected_hold_resume_calls_count) { 1 + temporary_files_count + [".", ".."].size }

      context "with a block" do
        it "matches the ruby behavior without monkey patching" do
          test_with_and_without_monkey_patch do
            files = []

            Dir.foreach(temporary_directory, encoding: "UTF-8") { |it| files << it }

            expect(files).to contain_exactly("file1", "file2", "file3", ".", "..")
          end
        end

        it "allows signals to arrive inside the user block" do
          test_with_monkey_patch do
            ran_assertion = false

            Dir.foreach(temporary_directory, encoding: "UTF-8") do
              expect_sigprof_to_be(:unblocked)
              ran_assertion = true
            end

            expect(ran_assertion).to be true
          end
        end
      end

      context "without a block" do
        it "matches the ruby behavior without monkey patching" do
          test_with_and_without_monkey_patch do
            expect(Dir.foreach(temporary_directory, encoding: "UTF-8").to_a)
              .to include("file1", "file2", "file3", ".", "..")
          end
        end
      end
    end

    describe ".glob" do
      before do
        File.write("#{temporary_directory}/.hidden_file1", ".hidden_file1")
      end

      let(:expected_files_result) { [".hidden_file1", "file1", "file2"] }

      context "with a block" do
        let(:expected_hold_resume_calls_count) { 1 + expected_files_result.size }

        it "matches the ruby behavior without monkey patching" do
          test_with_and_without_monkey_patch do
            files = []

            Dir.glob(["*1", "*2"], base: temporary_directory, flags: File::FNM_DOTMATCH) { |it| files << it }

            expect(files).to contain_exactly(*expected_files_result)
          end
        end

        it "allows signals to arrive inside the user block" do
          test_with_monkey_patch do
            ran_assertion = false

            Dir.glob(["*1", "*2"], base: temporary_directory, flags: File::FNM_DOTMATCH) do
              expect_sigprof_to_be(:unblocked)
              ran_assertion = true
            end

            expect(ran_assertion).to be true
          end
        end
      end

      context "without a block" do
        # You may be wondering why this one has a call count of 1 when for instance .foreach and each_child have a call
        # count of > 1. The difference is the "without a block" versions of those calls **return an enumerator** and
        # the enumerator then just calls the block version when executed.
        #
        # This is not what happens with glob -- glob never returns an enumerator, so the "without a block" version
        # does not get turned into a "with a block" call.
        let(:expected_hold_resume_calls_count) { 1 }

        it "matches the ruby behavior without monkey patching" do
          test_with_and_without_monkey_patch do
            expect(Dir.glob(["*1", "*2"], base: temporary_directory, flags: File::FNM_DOTMATCH))
              .to contain_exactly(*expected_files_result)
          end
        end
      end
    end

    describe ".home" do
      it "matches the ruby behavior without monkey patching" do
        test_with_and_without_monkey_patch do
          expect(Dir.home).to start_with("/")
        end
      end
    end
  end

  describe "DirInstanceMonkeyPatches" do
    let(:dir) { Dir.new(temporary_directory) }

    describe "#each" do
      let(:expected_hold_resume_calls_count) { 1 + temporary_files_count + [".", ".."].size }

      context "with a block" do
        it "matches the ruby behavior without monkey patching" do
          test_with_and_without_monkey_patch do
            files = []

            dir.each { |it| files << it }

            expect(files).to contain_exactly("file1", "file2", "file3", ".", "..")
          end
        end

        it "allows signals to arrive inside the user block" do
          test_with_monkey_patch do
            ran_assertion = false

            dir.each do
              expect_sigprof_to_be(:unblocked)
              ran_assertion = true
            end

            expect(ran_assertion).to be true
          end
        end
      end

      context "without a block" do
        it "matches the ruby behavior without monkey patching" do
          test_with_and_without_monkey_patch do
            expect(dir.each.to_a).to contain_exactly("file1", "file2", "file3", ".", "..")
          end
        end
      end
    end

    describe "#each_child" do
      before { skip("API not available on Ruby 2.5") if RUBY_VERSION.start_with?("2.5.") }

      let(:expected_hold_resume_calls_count) { 1 + temporary_files_count }

      context "with a block" do
        it "matches the ruby behavior without monkey patching" do
          test_with_and_without_monkey_patch do
            files = []

            dir.each_child { |it| files << it }

            expect(files).to contain_exactly("file1", "file2", "file3")
          end
        end

        it "allows signals to arrive inside the user block" do
          test_with_monkey_patch do
            ran_assertion = false

            dir.each_child do
              expect_sigprof_to_be(:unblocked)
              ran_assertion = true
            end

            expect(ran_assertion).to be true
          end
        end
      end

      context "without a block" do
        it "matches the ruby behavior without monkey patching" do
          test_with_and_without_monkey_patch do
            expect(dir.each_child.to_a).to include("file1", "file2", "file3")
          end
        end
      end
    end

    describe "#children" do
      before { skip("API not available on Ruby 2.5") if RUBY_VERSION.start_with?("2.5.") }

      it "matches the ruby behavior without monkey patching" do
        test_with_and_without_monkey_patch do
          expect(dir.children).to contain_exactly("file1", "file2", "file3")
        end
      end
    end

    describe "#tell" do
      it "matches the ruby behavior without monkey patching" do
        test_with_and_without_monkey_patch do
          expect(dir.tell).to be_a_kind_of(Integer)
        end
      end
    end

    describe "#pos" do
      it "matches the ruby behavior without monkey patching" do
        test_with_and_without_monkey_patch do
          expect(dir.pos).to be_a_kind_of(Integer)
        end
      end
    end
  end

  def test_with_and_without_monkey_patch(&testcase)
    yield
    test_with_monkey_patch(&testcase)
  end

  def test_with_monkey_patch(in_fork: true, &testcase)
    wrapped_testcase = proc do
      RSpec::Mocks.space.proxy_for(Datadog::Profiling::Collectors::CpuAndWallTimeWorker).reset

      allow(Datadog::Profiling::Collectors::CpuAndWallTimeWorker)
        .to receive(:_native_hold_signals).and_call_original
      allow(Datadog::Profiling::Collectors::CpuAndWallTimeWorker)
        .to receive(:_native_resume_signals).and_call_original

      Datadog::Profiling::Ext::DirMonkeyPatches.apply!
      yield

      expect(Datadog::Profiling::Collectors::CpuAndWallTimeWorker)
        .to have_received(:_native_hold_signals).exactly(expected_hold_resume_calls_count).times
      expect(Datadog::Profiling::Collectors::CpuAndWallTimeWorker)
        .to have_received(:_native_resume_signals).exactly(expected_hold_resume_calls_count).times
    end

    if in_fork
      expect_in_fork(&wrapped_testcase)
    else
      wrapped_testcase.call
    end
  end

  def expect_sigprof_to_be(state)
    raise ArgumentError unless [:blocked, :unblocked].include?(state)

    expect(
      Datadog::Profiling::Collectors::CpuAndWallTimeWorker::Testing._native_is_sigprof_blocked_in_current_thread
    ).to be(state == :blocked), "Sigprof was expected to be #{state}, but it's actually not"
  end
end
