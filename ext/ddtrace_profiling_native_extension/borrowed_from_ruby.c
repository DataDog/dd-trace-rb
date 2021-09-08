// -----------------------------------------------------------------------------
// The sources below are modified versions of code extracted from the Ruby project.
// The Ruby project copyright and license follow:
// -----------------------------------------------------------------------------

// Ruby is copyrighted free software by Yukihiro Matsumoto <matz@netlab.jp>.
// You can redistribute it and/or modify it under either the terms of the
// 2-clause BSDL (see the file BSDL), or the conditions below:

// 1. You may make and give away verbatim copies of the source form of the
//    software without restriction, provided that you duplicate all of the
//    original copyright notices and associated disclaimers.

// 2. You may modify your copy of the software in any way, provided that
//    you do at least ONE of the following:

//    a. place your modifications in the Public Domain or otherwise
//       make them Freely Available, such as by posting said
//       modifications to Usenet or an equivalent medium, or by allowing
//       the author to include your modifications in the software.

//    b. use the modified software only within your corporation or
//       organization.

//    c. give non-standard binaries non-standard names, with
//       instructions on where to get the original software distribution.

//    d. make other distribution arrangements with the author.

// 3. You may distribute the software in object code or binary form,
//    provided that you do at least ONE of the following:

//    a. distribute the binaries and library files of the software,
//       together with instructions (in the manual page or equivalent)
//       on where to get the original distribution.

//    b. accompany the distribution with the machine-readable source of
//       the software.

//    c. give non-standard binaries non-standard names, with
//       instructions on where to get the original software distribution.

//    d. make other distribution arrangements with the author.

// 4. You may modify and include the part of the software into any other
//    software (possibly commercial).  But some files in the distribution
//    are not written by the author, so that they are not under these terms.

//    For the list of those files and their copying conditions, see the
//    file LEGAL.

// 5. The scripts and library files supplied as input to or produced as
//    output from the software do not automatically fall under the
//    copyright of the software, but belong to whomever generated them,
//    and may be sold commercially, and may be aggregated with this
//    software.

// 6. THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR
//    IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
//    WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
//    PURPOSE.

#include "extconf.h"
#include RUBY_MJIT_HEADER

/**********************************************************************
  vm_backtrace.c -
  Copyright (C) 1993-2012 Yukihiro Matsumoto
**********************************************************************/

inline static int calc_lineno(const rb_iseq_t *iseq, const VALUE *pc)
{
    VM_ASSERT(iseq);
    VM_ASSERT(iseq->body);
    VM_ASSERT(iseq->body->iseq_encoded);
    VM_ASSERT(iseq->body->iseq_size);
    if (! pc) {
        /* This can happen during VM bootup. */
        VM_ASSERT(iseq->body->type == ISEQ_TYPE_TOP);
        VM_ASSERT(! iseq->body->local_table);
        VM_ASSERT(! iseq->body->local_table_size);
        return 0;
    }
    else {
        ptrdiff_t n = pc - iseq->body->iseq_encoded;
        VM_ASSERT(n <= iseq->body->iseq_size);
        VM_ASSERT(n >= 0);
        ASSUME(n >= 0);
        size_t pos = n; /* no overflow */
        if (LIKELY(pos)) {
            /* use pos-1 because PC points next instruction at the beginning of instruction */
            pos--;
        }
#if VMDEBUG && defined(HAVE_BUILTIN___BUILTIN_TRAP)
        else {
            /* SDR() is not possible; that causes infinite loop. */
            rb_print_backtrace();
            __builtin_trap();
        }
#endif
        return rb_iseq_line_no(iseq, pos);
    }
}

int borrowed_from_ruby_sources_rb_profile_frames(VALUE thread, int start, int limit, VALUE *buff, int *lines)
{
    // In here we're assuming that what we got is really a Thread or its subclass
    rb_thread_t *thread_pointer = (rb_thread_t*) DATA_PTR(thread);

    rb_execution_context_t *ec = thread_pointer->ec;
    int i;
    const rb_control_frame_t *cfp = ec->cfp, *end_cfp = RUBY_VM_END_CONTROL_FRAME(ec);
    const rb_callable_method_entry_t *cme;

    for (i=0; i<limit && cfp != end_cfp;) {
        if (VM_FRAME_RUBYFRAME_P(cfp)) {
            if (start > 0) {
                start--;
                continue;
            }

            /* record frame info */
            cme = rb_vm_frame_method_entry(cfp);
            if (cme && cme->def->type == VM_METHOD_TYPE_ISEQ) {
                buff[i] = (VALUE)cme;
            }
            else {
                buff[i] = (VALUE)cfp->iseq;
            }

            if (lines) lines[i] = calc_lineno(cfp->iseq, cfp->pc);

            i++;
        }
        cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
    }

    return i;
}
