.PHONY: miteruby-virel-test
miteruby-virel-test:
	$(CC) $(INCFLAGS) $(CPPFLAGS) $(CFLAGS) $(srcdir)/../../spec/datadog/profiling/miteruby_virel_serializer_test.c $(filter-out virel_serializer.o,$(OBJS)) $(LIBPATH) $(ldflags) $(TEST_RUBY_LIBS) $(LIBS) -o $(VIREL_TEST_BINARY)
