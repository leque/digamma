#   Makefile for Linux, Darwin
#   Requirements: GNU Make, clang++
#   Options: DESTDIR, PREFIX, DATAMODEL(ILP32/LP64)

PROG = digamma

PREFIX = /usr/local

CPPFLAGS = -DNDEBUG -DSYSTEM_SHARE_PATH='"$(DESTDIR)$(PREFIX)/share/$(PROG)"' -DSYSTEM_EXTENSION_PATH='"$(DESTDIR)$(PREFIX)/lib/$(PROG)"'

CXX = clang++

CXXFLAGS = -pipe -O3 -fstrict-aliasing

SRCS 	 = file.cpp main.cpp vm0.cpp object_heap_compact.cpp subr_flonum.cpp vm1.cpp object_set.cpp \
	   subr_hash.cpp vm2.cpp object_slab.cpp subr_list.cpp interpreter.cpp serialize.cpp nanoasm.cpp \
           vm3.cpp port.cpp subr_others.cpp arith.cpp printer.cpp subr_port.cpp subr_r5rs_arith.cpp \
	   equiv.cpp reader.cpp subr_base.cpp bag.cpp uuid.cpp subr_thread.cpp \
           subr_unicode.cpp hash.cpp subr_base_arith.cpp ucs4.cpp ioerror.cpp subr_bitwise.cpp utf8.cpp \
	   main.cpp subr_bvector.cpp violation.cpp object_factory.cpp subr_file.cpp subr_process.cpp \
           object_heap.cpp subr_fixnum.cpp bit.cpp list.cpp fasl.cpp socket.cpp subr_socket.cpp

VPATH 	 = src

UNAME 	 = $(shell uname -a)

ifndef DATAMODEL
  ifeq (,$(shell echo | $(CXX) -E -dM - | grep '__LP64__'))
    DATAMODEL = ILP32
    CPPFLAGS += -DDEFAULT_HEAP_LIMIT=32
  else
    DATAMODEL = LP64
    CPPFLAGS += -DDEFAULT_HEAP_LIMIT=64
  endif
endif

ifneq (,$(findstring Linux, $(UNAME)))
  CXXFLAGS += -pthread -fomit-frame-pointer
  ifneq (,$(findstring arm, $(UNAME)))
    ifeq ($(DATAMODEL), ILP32)
      CXXFLAGS += -march=armv7-a
    else
      CXXFLAGS += -march=armv8-a
    endif
  endif
  ifneq (,$(findstring x86, $(UNAME)))
    CXXFLAGS += -momit-leaf-frame-pointer
    ifeq ($(DATAMODEL), ILP32)
      CXXFLAGS += -march=x86
    else
      CXXFLAGS += -march=x86-64
    endif
  endif
  LDLIBS = -pthread -Wl,--no-as-needed -ldl
endif

ifneq (,$(findstring Darwin, $(UNAME)))
    CXXFLAGS += -fomit-frame-pointer -momit-leaf-frame-pointer
  ifeq ($(DATAMODEL), ILP32)
    CXXFLAGS += -m32
  else
    CXXFLAGS += -m64
  endif
endif

OBJS = $(patsubst %.cpp, %.o, $(filter %.cpp, $(SRCS))) $(patsubst %.s, %.o, $(filter %.s, $(SRCS)))
DEPS = $(patsubst %.cpp, %.d, $(filter %.cpp, $(SRCS)))

.PHONY: all install uninstall sitelib stdlib extension check bench clean distclean

all: $(PROG) $(EXTS)
	@mkdir -p -m755 $(HOME)/.digamma

$(PROG): $(OBJS)
	$(CXX) $(LDFLAGS) $(LDLIBS) -o $@ $^

vm1.s: vm1.cpp
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) \
	-fverbose-asm -masm=att -S src/vm1.cpp

vm1.o: vm1.cpp
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) \
	-c src/vm1.cpp

install: all stdlib sitelib extension
	mkdir -p -m755 $(DESTDIR)$(PREFIX)/bin
	cp $(PROG) $(DESTDIR)$(PREFIX)/bin/$(PROG)
	chmod 755 $(DESTDIR)$(PREFIX)/bin/$(PROG)

uninstall:
	-rm -rf $(DESTDIR)$(PREFIX)/share/$(PROG)/stdlib
	-rm -rf $(DESTDIR)$(PREFIX)/share/$(PROG)/sitelib
	-rm -rf $(DESTDIR)$(PREFIX)/lib/$(PROG)
	-rm -f $(DESTDIR)$(PREFIX)/bin/$(PROG)
	-rmdir $(DESTDIR)$(PREFIX)/share/$(PROG)

stdlib:
	mkdir -p -m755 $(DESTDIR)$(PREFIX)/share/$(PROG)/stdlib
	find stdlib -type f -name '*.scm' | cpio -pdu $(DESTDIR)$(PREFIX)/share/$(PROG)
	find $(DESTDIR)$(PREFIX)/share/$(PROG)/stdlib -type d -exec chmod 755 {} \;
	find $(DESTDIR)$(PREFIX)/share/$(PROG)/stdlib -type f -exec chmod 644 {} \;

sitelib:
	mkdir -p -m755 $(DESTDIR)$(PREFIX)/share/$(PROG)/sitelib
	find sitelib -type f -name '*.scm' | cpio -pdu $(DESTDIR)$(PREFIX)/share/$(PROG)
	find $(DESTDIR)$(PREFIX)/share/$(PROG)/sitelib -type d -exec chmod 755 {} \;
	find $(DESTDIR)$(PREFIX)/share/$(PROG)/sitelib -type f -exec chmod 644 {} \;

extension:
	mkdir -p -m755 $(DESTDIR)$(PREFIX)/lib/$(PROG)
	find . -type f -name '*.dylib' | cpio -pdu $(DESTDIR)$(PREFIX)/lib/$(PROG)
	find $(DESTDIR)$(PREFIX)/lib/$(PROG) -type d -exec chmod 755 {} \;
	find $(DESTDIR)$(PREFIX)/lib/$(PROG) -type f -exec chmod 755 {} \;

check: all
	@echo '----------------------------------------'
	@echo 'r4rstest.scm:'
	@./$(PROG) --heap-limit=128 --acc=/tmp --clean-acc --sitelib=./test:./sitelib:./stdlib ./test/r4rstest.scm
	@echo '----------------------------------------'
	@echo 'tspl.scm:'
	@./$(PROG) --heap-limit=128 --acc=/tmp --clean-acc --sitelib=./test:./sitelib:./stdlib ./test/tspl.scm
	@echo '----------------------------------------'
	@echo 'arith.scm:'
	@./$(PROG) --heap-limit=128 --acc=/tmp --clean-acc --sitelib=./test:./sitelib:./stdlib ./test/arith.scm
	@echo '----------------------------------------'
	@echo 'r5rs_pitfall.scm:'
	@./$(PROG) --r6rs --heap-limit=128 --acc=/tmp --clean-acc --sitelib=./test:./sitelib:./stdlib ./test/r5rs_pitfall.scm
	@echo '----------------------------------------'
	@echo 'syntax-rule-stress-test.scm:'
	@./$(PROG) --heap-limit=128 --acc=/tmp --clean-acc --sitelib=./test:./sitelib:./stdlib ./test/syntax-rule-stress-test.scm
	@echo '----------------------------------------'
	@echo 'r6rs.scm:'
	@./$(PROG) --r6rs --heap-limit=128 --acc=/tmp --clean-acc --sitelib=./test:./sitelib:./stdlib ./test/r6rs.scm
	@echo '----------------------------------------'
	@echo 'r6rs-lib.scm:'
	@./$(PROG) --r6rs --heap-limit=128 --acc=/tmp --clean-acc --sitelib=./test:./sitelib:./stdlib ./test/r6rs-lib.scm
	@echo '----------------------------------------'
	@echo 'r6rs-more.scm:'
	@./$(PROG) --r6rs --heap-limit=128 --acc=/tmp --clean-acc --sitelib=./test:./sitelib:./stdlib ./test/r6rs-more.scm
	@echo '----------------------------------------'
	@echo 'r7rs-test.scm:'
	@./$(PROG) --r7rs --top-level-program --heap-limit=128 --acc=/tmp --clean-acc --sitelib=./test:./sitelib:./stdlib ./test/r7rs-test.scm
	@echo '----------------------------------------'
	@echo 'Passed all tests'
	@rm -f ./test/tmp*

eval: all
	./$(PROG) --verbose --heap-limit=128 --acc=/tmp --clean-acc --sitelib=./sitelib:./stdlib

bench: all
	./$(PROG) --heap-limit=128 --acc=/tmp --clean-acc --sitelib=./test:./sitelib:./stdlib -- bench/run-digamma.scm

clean:
	rm -f *.o *.d *.dylib
	rm -f $(HOME)/.digamma/*.cache
	rm -f $(HOME)/.digamma/*.time

distclean: clean
	rm -f tmp1 tmp2 tmp3 spheres.pgm
	rm -f ./test/tmp*
	rm -f ./bench/gambit-benchmarks/tmp*
	rm -f ./bench/gambit-benchmarks/spheres.pgm
	rm -f $(PROG)

moreclean: distclean
	find . -type f -name .DS_Store -print0 | xargs -0 rm -f
	find . -type f -name '*~' -print0 | xargs -0 rm -f

%.d: %.cpp
	$(SHELL) -ec '$(CXX) -MM $(CPPFLAGS) $< | sed '\''s/\($*\)\.o[ :]*/\1.o $@ : /g'\'' > $@; [ -s $@ ] || rm -f $@'

ifeq ($(findstring clean, $(MAKECMDGOALS)), )
  ifeq ($(findstring uninstall, $(MAKECMDGOALS)), )
    -include $(DEPS)
  endif
endif
