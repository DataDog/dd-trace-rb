#include "libdatadog_helpers.h"

#include <ruby.h>

const char *ruby_value_type_to_string(enum ruby_value_type type) {
  switch (type) {
    case(RUBY_T_NONE    ): return "T_NONE";
    case(RUBY_T_OBJECT  ): return "T_OBJECT";
    case(RUBY_T_CLASS   ): return "T_CLASS";
    case(RUBY_T_MODULE  ): return "T_MODULE";
    case(RUBY_T_FLOAT   ): return "T_FLOAT";
    case(RUBY_T_STRING  ): return "T_STRING";
    case(RUBY_T_REGEXP  ): return "T_REGEXP";
    case(RUBY_T_ARRAY   ): return "T_ARRAY";
    case(RUBY_T_HASH    ): return "T_HASH";
    case(RUBY_T_STRUCT  ): return "T_STRUCT";
    case(RUBY_T_BIGNUM  ): return "T_BIGNUM";
    case(RUBY_T_FILE    ): return "T_FILE";
    case(RUBY_T_DATA    ): return "T_DATA";
    case(RUBY_T_MATCH   ): return "T_MATCH";
    case(RUBY_T_COMPLEX ): return "T_COMPLEX";
    case(RUBY_T_RATIONAL): return "T_RATIONAL";
    case(RUBY_T_NIL     ): return "T_NIL";
    case(RUBY_T_TRUE    ): return "T_TRUE";
    case(RUBY_T_FALSE   ): return "T_FALSE";
    case(RUBY_T_SYMBOL  ): return "T_SYMBOL";
    case(RUBY_T_FIXNUM  ): return "T_FIXNUM";
    case(RUBY_T_UNDEF   ): return "T_UNDEF";
    case(RUBY_T_IMEMO   ): return "T_IMEMO";
    case(RUBY_T_NODE    ): return "T_NODE";
    case(RUBY_T_ICLASS  ): return "T_ICLASS";
    case(RUBY_T_ZOMBIE  ): return "T_ZOMBIE";
    #ifdef RUBY_T_MOVED // Introduced in Ruby 2.7
    case(RUBY_T_MOVED   ): return "T_MOVED";
    #endif
                  default: return "T_UNKNOWN_OR_MISSING_RUBY_VALUE_TYPE_ENTRY";
  }
}

ddog_CharSlice ruby_value_type_to_char_slice(enum ruby_value_type type) {
  switch (type) {
    case(RUBY_T_NONE    ): return DDOG_CHARSLICE_C("T_NONE");
    case(RUBY_T_OBJECT  ): return DDOG_CHARSLICE_C("T_OBJECT");
    case(RUBY_T_CLASS   ): return DDOG_CHARSLICE_C("T_CLASS");
    case(RUBY_T_MODULE  ): return DDOG_CHARSLICE_C("T_MODULE");
    case(RUBY_T_FLOAT   ): return DDOG_CHARSLICE_C("T_FLOAT");
    case(RUBY_T_STRING  ): return DDOG_CHARSLICE_C("T_STRING");
    case(RUBY_T_REGEXP  ): return DDOG_CHARSLICE_C("T_REGEXP");
    case(RUBY_T_ARRAY   ): return DDOG_CHARSLICE_C("T_ARRAY");
    case(RUBY_T_HASH    ): return DDOG_CHARSLICE_C("T_HASH");
    case(RUBY_T_STRUCT  ): return DDOG_CHARSLICE_C("T_STRUCT");
    case(RUBY_T_BIGNUM  ): return DDOG_CHARSLICE_C("T_BIGNUM");
    case(RUBY_T_FILE    ): return DDOG_CHARSLICE_C("T_FILE");
    case(RUBY_T_DATA    ): return DDOG_CHARSLICE_C("T_DATA");
    case(RUBY_T_MATCH   ): return DDOG_CHARSLICE_C("T_MATCH");
    case(RUBY_T_COMPLEX ): return DDOG_CHARSLICE_C("T_COMPLEX");
    case(RUBY_T_RATIONAL): return DDOG_CHARSLICE_C("T_RATIONAL");
    case(RUBY_T_NIL     ): return DDOG_CHARSLICE_C("T_NIL");
    case(RUBY_T_TRUE    ): return DDOG_CHARSLICE_C("T_TRUE");
    case(RUBY_T_FALSE   ): return DDOG_CHARSLICE_C("T_FALSE");
    case(RUBY_T_SYMBOL  ): return DDOG_CHARSLICE_C("T_SYMBOL");
    case(RUBY_T_FIXNUM  ): return DDOG_CHARSLICE_C("T_FIXNUM");
    case(RUBY_T_UNDEF   ): return DDOG_CHARSLICE_C("T_UNDEF");
    case(RUBY_T_IMEMO   ): return DDOG_CHARSLICE_C("T_IMEMO");
    case(RUBY_T_NODE    ): return DDOG_CHARSLICE_C("T_NODE");
    case(RUBY_T_ICLASS  ): return DDOG_CHARSLICE_C("T_ICLASS");
    case(RUBY_T_ZOMBIE  ): return DDOG_CHARSLICE_C("T_ZOMBIE");
    #ifdef RUBY_T_MOVED // Introduced in Ruby 2.7
    case(RUBY_T_MOVED   ): return DDOG_CHARSLICE_C("T_MOVED");
    #endif
                  default: return DDOG_CHARSLICE_C("T_UNKNOWN_OR_MISSING_RUBY_VALUE_TYPE_ENTRY");
  }
}
