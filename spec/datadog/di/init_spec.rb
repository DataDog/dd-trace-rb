require "datadog/di/spec_helper"
require 'open3'

RSpec.describe 'DI initializer' do
  di_test

  context 'when loaded initially into a clean process' do
    it 'loads only DI code tracker' do
      script = <<-SCRIPT
        if defined?(Datadog) && Datadog.constants != %i(VERSION)
          raise "Datadog code loaded too early"
        end

        require 'datadog/di/init'

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
      out, status = Open3.capture2e('ruby', stdin_data: script)
      unless status.exitstatus == 0
        fail("Test script failed with exist status #{status.exitstatus}:\n#{out}")
      end
    end
  end
end
