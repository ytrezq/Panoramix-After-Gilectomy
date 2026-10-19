// Deterministic parallelism: a loop whose iterations run on threads (the
// functions to decompile, the parts of the postprocessing that are the same
// work for every function).
#pragma once

#include <functional>

#include "core/base.hpp"

namespace pan {

// fn(i) for every i in 0..n-1, on min(threads, n) threads at once: the
// caller's thread and min(threads, n) - 1 workers made by platform::spawn with
// a stack of limits::WORKER_STACK (64 MiB, the recursions go as deep as the
// expressions nest). An atomic index hands out the iterations, in no fixed
// order and on no fixed thread: fn(i) puts its result at index i of the
// caller's storage, so the output doesn't depend on the thread count. Returns
// when all are done. threads <= 1 (or n == 1): this thread alone, in order.
// Fewer workers when the system can't start them (this thread does the rest).
//
// fn handles its own errors (a job's error is its result) and installs its own
// thread-local state (context, budget: Budget::attach_thread()) - nothing of
// the caller's thread is carried to the workers. An exception that escapes fn
// anyway stops the handing out; the first one is rethrown here once every
// thread is done.
void parallel_for(usize n, usize threads, const std::function<void(usize)>& fn);

}  // namespace pan
