#pragma once

#include "../private_vm_api_access.h"

#define NAME verstable_mark_cme_iseq_map
#define KEY_TY miteruby_event_frame_refs_t
#define VAL_TY miteruby_cme_iseq_id_t
#define HEADER_MODE
#include "hashtable/verstable.h"
