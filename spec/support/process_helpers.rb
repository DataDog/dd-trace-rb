# frozen_string_literal: true

RSpec.shared_context 'with mocked process environment' do
  def reset_memoized_variables!
    [:@serialized, :@tags].each do |variable|
      Datadog::Core::Environment::Process.remove_instance_variable(variable) if
        Datadog::Core::Environment::Process.instance_variable_defined?(variable)
    end
  end

  let(:program_name) { 'bin/rspec' }
  let(:pwd) { '/app' }

  around do |example|
    @original_0 = $0
    $0 = program_name
    example.run
    $0 = @original_0
  end

  before do
    allow(Dir).to receive(:pwd).and_return(pwd)
    allow(File).to receive(:expand_path).and_call_original
    allow(File).to receive(:expand_path).with('.').and_return('/app')
    reset_memoized_variables!
  end

  after do
    reset_memoized_variables!
  end
end
