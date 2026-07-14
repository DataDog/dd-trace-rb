# frozen_string_literal: true

require "datadog/di/spec_helper"
require 'open3'

# DI source files call Datadog::DI.reraise_if_fatal in their catch-all rescues.
# That helper is defined in datadog/di/fatal_exceptions, which is loaded via
# datadog/di/base (the DI boot path, MRI >= 2.6 only). Files that can be loaded
# outside that path -- di/remote via core remote config (capabilities.rb), and
# di/instrumenter required directly by specs -- must require fatal_exceptions
# themselves, otherwise the rescue path raises NoMethodError while handling
# another exception.
RSpec.describe 'DI fatal_exceptions availability when loaded standalone' do
  di_test

  %w[
    datadog/di/remote
    datadog/di/instrumenter
  ].each do |file|
    it "defines Datadog::DI.reraise_if_fatal after requiring #{file}" do
      script = <<-SCRIPT
        require '#{file}'
        unless Datadog::DI.respond_to?(:reraise_if_fatal)
          raise "reraise_if_fatal undefined after requiring #{file}"
        end
      SCRIPT
      out, status = Open3.capture2e('ruby', stdin_data: script)
      expect(status.exitstatus).to eq(0), "subprocess failed for #{file}: #{out}"
    end
  end
end
