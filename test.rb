require 'ddtrace'

Datadog.configure do |c|
    c.agent.host = "0.0.0.0"
end

transport_options = {
  agent_settings: Datadog::Core::Configuration::AgentSettingsResolver.call(Datadog.configuration)
}

require 'datadog/core/transport/http'

transport_v7 = Datadog::Core::Transport::HTTP.v7(**transport_options.dup)

CAP_ASM_ACTIVATION                = 1 << 1 # Remote activation via ASM_FEATURES product
CAP_ASM_IP_BLOCKING               = 1 << 2 # accept IP blocking data from ASM_DATA product
CAP_ASM_DD_RULES                  = 1 << 3 # read ASM rules from ASM_DD product
CAP_ASM_EXCLUSIONS                = 1 << 4 # exclusion filters (passlist) via ASM product
CAP_ASM_REQUEST_BLOCKING          = 1 << 5 # can block on request info
CAP_ASM_RESPONSE_BLOCKING         = 1 << 6 # can block on response info
CAP_ASM_USER_BLOCKING             = 1 << 7 # accept user blocking data from ASM_DATA product
CAP_ASM_CUSTOM_RULES              = 1 << 8 # accept custom rules
CAP_ASM_CUSTOM_BLOCKING_RESPONSE  = 1 << 9 # supports custom http code or redirect sa blocking response

capabilities = [
  CAP_ASM_IP_BLOCKING,
  CAP_ASM_USER_BLOCKING,
  CAP_ASM_CUSTOM_RULES,
  CAP_ASM_EXCLUSIONS,
  CAP_ASM_REQUEST_BLOCKING,
  CAP_ASM_RESPONSE_BLOCKING,
  CAP_ASM_DD_RULES,
].reduce(&:|)

capabilities_binary = capabilities
  .to_s(16)
  .tap { |s| s.size.odd? && s.prepend('0') }
  .scan(/\h\h/)
  .map { |e| e.to_i(16) }
  .pack('C*')

products = [
  'ASM_DD',       # Datadog employee issued configuration
  'ASM',          # customer issued configuration (rulesets, passlist...)
  'ASM_FEATURES', # capabilities
  'ASM_DATA',     # config files (IP addresses or users for blocking)
]

state = OpenStruct.new(
  {
    root_version: 1,              # unverified mode, so 1
    targets_version: 0,           # from scratch, so zero
    config_states: [],            # from scratch, so empty
    has_error: false,             # from scratch, so false
    error: '',                    # from scratch, so blank
    opaque_backend_state: '',     # from scratch, so blank
  }
)

id = SecureRandom.uuid # client id

payload = {
  client: {
    state: {
      root_version:         state.root_version,
      targets_version:      state.targets_version,
      config_states:        state.config_states,
      has_error:            state.has_error,
      error:                state.error,
      backend_client_state: state.opaque_backend_state,
    },
    id: id,
    products: products,
    is_tracer: true,
    is_agent: false,
    client_tracer: {
      runtime_id:      Datadog::Core::Environment::Identity.id,
      language:        Datadog::Core::Environment::Identity.lang,
      tracer_version:  Datadog::Core::Environment::Identity.tracer_version,
      service:         Datadog.configuration.service,
      env:             Datadog.configuration.env,
    # app_version:     app_version,   # TODO: I don't know where this is in the tracer
      tags:            [],            # TODO: add nice tags!
    },
    # base64 is needed otherwise the Go agent fails with an unmarshal error
    capabilities: Base64.encode64(capabilities_binary).chomp,
  },
  cached_target_files: [
  # {
  #   path: '',
  #   length: 0,
  #   hashes: '';
  # }
  ],
}


res = transport_v7.send_config(payload)
require 'pry'; binding.pry
puts res.target_files
puts res.client_configs
puts res.targets
puts res.roots
