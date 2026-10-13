#pragma once

typedef struct idle_sampling_loop_state idle_sampling_loop_state;

// Must be called with the GVL held; keep self_instance alive while using the returned pointer.
idle_sampling_loop_state *idle_sampling_helper_get_state(VALUE self_instance);
void idle_sampling_helper_request_action(idle_sampling_loop_state *state, void (*run_action_function)(void));
