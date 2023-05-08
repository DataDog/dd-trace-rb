module DependencyHelpers
  def dependency(name, &block)
    if block
      let(name, &block)

      before do
        allow(Datadog::Core.dependency_registry).to receive(:resolve_component).and_call_original # TODO: does doing this twice mess up previous `.with(arg)` clauses?
        allow(Datadog::Core.dependency_registry).to receive(:resolve_component).with(name).and_return(send(name))
      end
    else
      let(name) { Datadog::Core.dependency_registry.resolve_component(name) }
    end
  end
end
