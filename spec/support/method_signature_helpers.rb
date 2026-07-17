RSpec::Matchers.define :be_signature_compatible_with do |real_method|
  match do |wrapper_method|
    @violations = Datadog::MethodSignatureHelpers.compatibility_violations(wrapper_method, real_method)
    @violations.empty?
  end

  failure_message do |wrapper_method|
    "expected #{wrapper_method.name} #{wrapper_method.parameters.inspect} to be signature-compatible " \
      "with #{real_method.name} #{real_method.parameters.inspect}, but: #{@violations.join(', ')}"
  end
end

module Datadog
  # Compares a contrib wrapper method's signature against the real method it wraps via `prepend`+`super`,
  # to catch wrappers that require arguments the real method doesn't need, or accept arguments it doesn't.
  #
  # Only meaningful when the real method exposes a real signature via `Method#parameters` (pure-Ruby gems).
  # C-extension methods often report a bare `[[:rest]]` regardless of their actual contract, which this
  # check cannot see through — those wrappers need a behavioral regression test instead.
  module MethodSignatureHelpers
    module_function

    def compatibility_violations(wrapper_method, real_method)
      wrapper_params = wrapper_method.parameters
      real_params = real_method.parameters

      violations = []

      wrapper_req = count(wrapper_params, :req)
      real_req = count(real_params, :req)
      violations << "wrapper requires #{wrapper_req} positional args but real method requires #{real_req}" if wrapper_req > real_req

      wrapper_positional_slots = wrapper_req + count(wrapper_params, :opt)
      real_positional_slots = real_req + count(real_params, :opt)
      if (has?(real_params, :rest) || real_positional_slots > wrapper_positional_slots) && !has?(wrapper_params, :rest)
        violations << 'wrapper does not forward extra positional args the real method accepts (missing *args)'
      end
      if has?(wrapper_params, :rest) && !has?(real_params, :rest) && real_positional_slots <= wrapper_positional_slots
        violations << 'wrapper accepts extra positional args the real method does not (unexpected *args)'
      end

      wrapper_keyreq = names(wrapper_params, :keyreq)
      real_keyreq = names(real_params, :keyreq)
      extra_required_kw = wrapper_keyreq - real_keyreq
      violations << "wrapper requires keywords the real method doesn't require: #{extra_required_kw}" unless extra_required_kw.empty?

      real_extra_kw = has?(real_params, :key) || has?(real_params, :keyrest)
      if real_extra_kw && !has?(wrapper_params, :keyrest)
        violations << 'wrapper does not forward extra keyword args the real method accepts (missing **kwargs)'
      end
      if has?(wrapper_params, :keyrest) && !real_extra_kw
        violations << 'wrapper accepts extra keyword args the real method does not (unexpected **kwargs)'
      end

      violations
    end

    def count(params, kind)
      params.count { |k, _| k == kind }
    end

    def has?(params, kind)
      params.any? { |k, _| k == kind }
    end

    def names(params, kind)
      params.select { |k, _| k == kind }.map { |_, name| name }
    end
  end
end
