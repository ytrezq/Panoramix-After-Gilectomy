// The test runner's main(): the one translation unit that compiles doctest's
// implementation. Every other cxx/tests/*_test.cpp only includes
// <doctest/doctest.h> and declares its TEST_CASEs; `make check` links them
// all with the library into one binary and runs it.
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>
