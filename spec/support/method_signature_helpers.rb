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
  # Compares a contrib wrapper method's signature against the real method it wraps via `super`,
  # to catch wrappers whose declared parameters don't line up with what the real method accepts.
  #
  # A bare `super` (no parens) forwards every parameter the wrapper *names* -- required or
  # optional, positional or keyword -- using whatever value it was called with, including
  # defaults that were never explicitly passed. So every named wrapper slot needs a matching
  # slot on the real method (or a splat on the real method to absorb it); wrapper splats are
  # always safe, since they only forward what the caller actually supplied.
  #
  # Only meaningful when the real method exposes a real signature via `Method#parameters` (pure-Ruby gems).
  # C-extension methods often report a bare `[[:rest]]` regardless of their actual contract, which this
  # check cannot see through — those wrappers need a behavioral regression test instead.
  #
  # Assumes the wrapper calls the real method via bare `super` (no parens). A wrapper that calls
  # `super(x)` or `super()` forwards a different set of arguments than what it declares, so the
  # "unset optional args"/"unrecognized optional keywords" checks below would false-positive on it.
  module MethodSignatureHelpers
    module_function

    def compatibility_violations(wrapper_method, real_method)
      wrapper_params = wrapper_method.parameters
      real_params = real_method.parameters

      violations = []
      violations.concat(positional_violations(wrapper_params, real_params))
      violations.concat(keyword_violations(wrapper_params, real_params))
      violations
    end

    def positional_violations(wrapper_params, real_params)
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
      if wrapper_positional_slots > real_positional_slots && !has?(real_params, :rest)
        violations << 'wrapper declares more positional args than the real method accepts; ' \
          'bare `super` would forward them even when unset (unset optional args)'
      end

      violations
    end

    def keyword_violations(wrapper_params, real_params)
      violations = []

      wrapper_keyreq = names(wrapper_params, :keyreq)
      real_keyreq = names(real_params, :keyreq)

      extra_required_kw = wrapper_keyreq - real_keyreq
      violations << "wrapper requires keywords the real method doesn't require: #{extra_required_kw}" unless extra_required_kw.empty?

      missing_required_kw = real_keyreq - (wrapper_keyreq + names(wrapper_params, :key))
      unless missing_required_kw.empty? || has?(wrapper_params, :keyrest)
        violations << "real method requires keywords the wrapper doesn't declare: #{missing_required_kw}"
      end

      if has?(real_params, :keyrest) && !has?(wrapper_params, :keyrest)
        violations << 'wrapper does not forward extra keyword args the real method accepts (missing **kwargs)'
      end
      real_has_any_keywords = has?(real_params, :key) || has?(real_params, :keyreq) || has?(real_params, :keyrest)
      if has?(wrapper_params, :keyrest) && !real_has_any_keywords
        violations << 'wrapper accepts extra keyword args the real method does not (unexpected **kwargs)'
      end

      wrapper_key = names(wrapper_params, :key)
      real_key = names(real_params, :key)
      unrecognized_optional_kw = wrapper_key - real_key - real_keyreq
      if !unrecognized_optional_kw.empty? && !has?(real_params, :keyrest)
        violations << "wrapper declares optional keywords the real method doesn't accept: #{unrecognized_optional_kw}; " \
          'bare `super` would forward them even when unset'
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
