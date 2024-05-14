REQUIRES = %w(
  datadog/appsec
  datadog/core
  datadog/kit
  datadog/profiling
  datadog/tracing
)

RSpec.describe 'require encapsulation' do
  before(:all) do
    # Permit Datadog::VERSION to be defined but no other constants.
    # See the note in gemspec about requiring 'datadog/version'.
    expect(defined?(Datadog)).to eq 'constant'
    expect(Datadog.constants).to eq([:VERSION])
  end

  REQUIRES.each do |req|
    context req do
      it 'loads' do
        pid = fork do
          require req
          exec('true')
        end

        Process.waitpid(pid)
        expect($?.exitstatus).to be 0
      end
    end
  end
end
