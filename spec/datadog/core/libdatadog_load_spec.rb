# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'libdatadog native extension' do
  # Smoke test to verify libdatadog loads on supported platforms.
  # This catches platform-specific issues that unit tests miss because they stub LIBDATADOG_API_FAILURE.
  #
  # Currently supported platforms:
  #   - Linux (x86_64, aarch64) - glibc and musl
  #   - macOS arm64 (Apple Silicon)
  #
  # Future platform support:
  #   - macOS x86_64 (Intel): Add `|| (PlatformHelpers.mac? && RUBY_PLATFORM.include?('x86_64'))` when libdatadog publishes x86_64-darwin gem
  #   - Windows: Add `|| PlatformHelpers.windows?` if/when libdatadog adds Windows support

  context 'on supported platforms' do
    before do
      skip 'Not a supported platform for libdatadog' unless supported_platform?
    end

    def supported_platform?
      return false unless PlatformHelpers.mri?

      PlatformHelpers.linux? || (PlatformHelpers.mac? && RUBY_PLATFORM.include?('arm64'))
    end

    it 'loads successfully' do
      puts "[libdatadog smoke test] Platform: #{RUBY_PLATFORM}"
      puts "[libdatadog smoke test] Ruby version: #{RUBY_VERSION}"
      puts "[libdatadog smoke test] Libdatadog pkgconfig folder: #{Libdatadog.pkgconfig_folder.inspect}"

      if Datadog::Core::LIBDATADOG_API_FAILURE
        puts "[libdatadog smoke test] FAILED: #{Datadog::Core::LIBDATADOG_API_FAILURE}"
      else
        puts "[libdatadog smoke test] SUCCESS: Native extension loaded"
      end

      expect(Datadog::Core::LIBDATADOG_API_FAILURE).to be_nil,
        "libdatadog failed to load: #{Datadog::Core::LIBDATADOG_API_FAILURE}"
    end
  end
end
