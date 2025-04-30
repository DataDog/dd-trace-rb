require "datadog/di/spec_helper"
require 'open3'

RSpec.describe 'DI initializer' do
  di_test

  # rubocop:disable Lint/ConstantDefinitionInBlock
  BOOTSTRAP_SCRIPT = <<-SCRIPT
    if defined?(Datadog) && Datadog.constants != %i(VERSION)
      raise "Datadog code loaded too early"
    end

    require 'datadog/di/preload'

    if Datadog.constants.sort != %i(DI VERSION)
      raise "Too many datadog components loaded: \#{Datadog.constants}"
    end

    unless Datadog::DI.code_tracker
      raise "Code tracker not instantiated"
    end

    unless Datadog::DI.code_tracker.send(:registry).empty?
      raise "Code tracker registry is not empty"
    end

    # Test load something
    require 'open3'

    if Datadog::DI.code_tracker.send(:registry).empty?
      raise "Code tracker did not add loaded file to registry"
    end

    unless Datadog::DI.code_tracker.send(:registry).detect { |key, value| key =~ /open3.rb\\z/ }
      raise "Loaded script not found in code tracker registry"
    end

    if Datadog.constants.sort != %i(DI VERSION)
      raise "Too many datadog components loaded at the end of execution: \#{Datadog.constants}"
    end
  SCRIPT
  # rubocop:enable Lint/ConstantDefinitionInBlock

  context 'when loaded initially into a clean process' do
    it 'loads only DI code tracker' do
      out, status = Open3.capture2e('ruby', stdin_data: BOOTSTRAP_SCRIPT)
      unless status.exitstatus == 0
        fail("Test script failed with exit status #{status.exitstatus}:\n#{out}")
      end
    end
  end

  context 'when entire library is loaded after di bootstrapper' do
    it 'keeps the mappings in code tracker prior to datadog load' do
      script = <<-SCRIPT
        #{BOOTSTRAP_SCRIPT}

        require 'datadog'

        # Should still have the open3 entry in code tracker
        unless Datadog::DI.code_tracker.send(:registry).detect { |key, value| key =~ /open3.rb\\z/ }
          raise "Loaded script not found in code tracker registry"
        end

        unless defined?(Datadog::Tracing)
          raise "Expected Datadog::Tracing to be defined after datadog was loaded"
        end
      SCRIPT
      out, status = Open3.capture2e('ruby', stdin_data: script)
      unless status.exitstatus == 0
        fail("Test script failed with exit status #{status.exitstatus}:\n#{out}")
      end
    end
  end
end
