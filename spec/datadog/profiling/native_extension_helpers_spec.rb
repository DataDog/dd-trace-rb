require "ext/datadog_profiling_native_extension/native_extension_helpers"
require "ext/libdatadog_extconf_helpers"
require "datadog/profiling/spec_helper"

RSpec.describe Datadog::Profiling::NativeExtensionHelpers::Supported do
  describe ".supported?" do
    subject(:supported?) { described_class.supported? }

    context "when there is an unsupported_reason" do
      before { allow(described_class).to receive(:unsupported_reason).and_return("Unsupported, sorry :(") }

      it { is_expected.to be false }
    end

    context "when there is no unsupported_reason" do
      before { allow(described_class).to receive(:unsupported_reason).and_return(nil) }

      it { is_expected.to be true }
    end
  end

  describe ".unsupported_reason" do
    subject(:unsupported_reason) do
      reason = described_class.unsupported_reason
      reason&.fetch(:reason)&.join("\n")
    end

    before do
      allow(RbConfig::CONFIG).to receive(:[]).and_call_original
    end

    context "when disabled via the DD_PROFILING_NO_EXTENSION environment variable" do
      with_env "DD_PROFILING_NO_EXTENSION" => "true"

      it { is_expected.to include "DD_PROFILING_NO_EXTENSION" }
    end

    context "when JRuby is used" do
      before { stub_const("RUBY_ENGINE", "jruby") }

      it { is_expected.to include "JRuby" }
    end

    context "when TruffleRuby is used" do
      before { stub_const("RUBY_ENGINE", "truffleruby") }

      it { is_expected.to include "TruffleRuby" }
    end

    context "when not on JRuby or TruffleRuby" do
      before { stub_const("RUBY_ENGINE", "ruby") }

      context "when on Windows" do
        before { expect(Gem).to receive(:win_platform?).and_return(true) }

        it { is_expected.to include "Windows" }
      end

      context "when on macOS" do
        around { |example| ClimateControl.modify("DD_PROFILING_MACOS_TESTING" => nil) { example.run } }

        before { stub_const("RUBY_PLATFORM", "x86_64-darwin19") }

        it { is_expected.to include "macOS" }
      end

      context "when not on Linux" do
        before { stub_const("RUBY_PLATFORM", "sparc-opensolaris") }

        it { is_expected.to include "operating system is not supported" }
      end

      context "when on Linux or on macOS with testing override enabled" do
        before { expect(Gem).to receive(:win_platform?).and_return(false) }

        context "when not on amd64 or arm64" do
          before { stub_const("RUBY_PLATFORM", "mipsel-linux") }

          it { is_expected.to include "architecture is not supported" }
        end

        shared_examples "supported ruby validation" do
          before { stub_const("RUBY_VERSION", "2.5.0") }

          shared_examples "libdatadog available" do
            context "when libdatadog fails to activate" do
              before do
                expect(Datadog::LibdatadogExtconfHelpers)
                  .to receive(:gem).with("libdatadog", Datadog::LibdatadogExtconfHelpers::LIBDATADOG_VERSION)
                  .and_raise(LoadError.new("Simulated error activating gem"))
              end

              it { is_expected.to include "exception during loading" }
            end

            context "when libdatadog successfully activates" do
              include_examples "libdatadog usable"
            end
          end

          shared_examples "libdatadog usable" do
            context "when libdatadog DOES NOT HAVE binaries for the current platform" do
              before do
                expect(Libdatadog).to receive(:pkgconfig_folder).and_return(nil)
                expect(Libdatadog).to receive(:available_binaries).and_return(%w[fooarch-linux bararch-linux-musl])
              end

              it { is_expected.to include "platform variant" }
            end

            context "when libdatadog HAS BINARIES for the current platform" do
              before { expect(Libdatadog).to receive(:pkgconfig_folder).and_return("/simulated/pkgconfig_folder") }

              it("marks the native extension as supported") { is_expected.to be nil }
            end
          end

          context "on a Ruby version where we CAN NOT use the MJIT header" do
            before { stub_const("Datadog::Profiling::NativeExtensionHelpers::CAN_USE_MJIT_HEADER", false) }

            include_examples "libdatadog available"
          end

          context "on a Ruby version where we CAN use the MJIT header" do
            before { stub_const("Datadog::Profiling::NativeExtensionHelpers::CAN_USE_MJIT_HEADER", true) }

            context "but DOES NOT have MJIT support" do
              before { expect(RbConfig::CONFIG).to receive(:[]).with("MJIT_SUPPORT").and_return("no") }

              it { is_expected.to include "without JIT" }
            end

            context "and DOES have MJIT support" do
              before { expect(RbConfig::CONFIG).to receive(:[]).with("MJIT_SUPPORT").and_return("yes") }

              include_examples "libdatadog available"
            end
          end
        end

        context "when on amd64 (x86-64) linux" do
          before { stub_const("RUBY_PLATFORM", "x86_64-linux") }

          include_examples "supported ruby validation"
        end

        context "when on arm64 (aarch64) linux" do
          before { stub_const("RUBY_PLATFORM", "aarch64-linux") }

          include_examples "supported ruby validation"
        end

        context "when macOS testing override is enabled" do
          around { |example| ClimateControl.modify("DD_PROFILING_MACOS_TESTING" => "true") { example.run } }

          context "when on amd64 (x86-64) macOS" do
            before { stub_const("RUBY_PLATFORM", "x86_64-darwin19") }

            include_examples "supported ruby validation"
          end

          context "when on arm64 macOS" do
            before { stub_const("RUBY_PLATFORM", "arm64-darwin21") }

            include_examples "supported ruby validation"
          end
        end
      end
    end
  end
end
