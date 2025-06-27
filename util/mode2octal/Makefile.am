# General automake options.
AUTOMAKE_OPTIONS = foreign no-dependencies
ACLOCAL_AMFLAGS = -I m4 -I gnulib-m4

# The list of subdirectories containing Makefiles.
SUBDIRS = m4 lib tests

AM_CPPFLAGS = -Ilib -I$(srcdir)/lib

# The list of programs that are built.
bin_PROGRAMS = mode2octal

# The source files of the 'hello' program.
mode2octal_SOURCES = mode2octal.c
mode2octal_LDADD = lib/libgnu.a

# Additional files to be distributed.
EXTRA_DIST = gnulib-m4/gnulib-cache.m4
