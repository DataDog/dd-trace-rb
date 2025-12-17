module LoadingHelpers
  module InstanceMethods
    def run_ruby_code_and_verify_no_output(code)
      out, status = Open3.capture2e('ruby', '-w', stdin_data: code)
      raise("Test script failed with exit status #{status.exitstatus}:\n#{out}") unless status.success?
      raise("Test script produced unexpected output: #{out}") unless out.empty?
    end
  end
end
