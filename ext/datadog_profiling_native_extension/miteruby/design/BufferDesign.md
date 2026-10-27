# Buffer design

The buffer accepts variable-size records from multiple producers and supplies
them to one consumer. Producers can write from signal handlers or other code.

This document gives the design reasons and limits for `buffer.h` and
`buffer.c`.

Go's CPU profiler and its `profBuf` buffer were the starting point.

## Design retained from Go

- **Word records without splits.** Each record starts with a `uint64_t`
  length prefix, followed by its payload. The length includes the prefix.
  A prefix with the value zero is a rewind marker: the consumer continues at
  array index zero. Records do not cross the end of the array, so the consumer
  can read each payload directly. The cost is skipped tail space, which
  occupies capacity until the consumer releases the record.

- **Publication and borrowed reads.** The producer copies the payload before
  it publishes the write position. It publishes a rewind marker and its record
  together, so the consumer cannot read a partial record. The consumer borrows
  the payload until the next read call releases its storage.
  This removes a consumer copy. Only one consumer can use the buffer.

- **Position counters.** Unsigned 32-bit positions count words and wrap.
  Their difference gives the occupied space and distinguishes full from empty.
  A power-of-two capacity keeps array indices correct when the counters wrap.
  The C11 atomic operations use sequential consistency to keep the publication
  and storage reuse rules simple.

- **Notification protocol.** The write position and notification flags share
  one atomic state. Compare-and-swap coordinates publication with the
  consumer's decision to sleep. An extra flag makes the consumer examine
  rejections and close again before sleep, because these do not advance the
  write position. An accepted write sends a notification at half capacity if
  the consumer sleeps. This decreases notifications, but records below that
  threshold can wait without a time limit until a rejection, close, or more data
  causes a notification.

## Changes and reasons

- **Producer lock in the buffer.** Go's CPU profiler owns the producer
  spinlock. This design moves that lock into each buffer so callers share one
  write interface. The lock serializes writes through publication and
  notification. The consumer does not acquire it. Contention calls libc
  `sched_yield()`.

- **Signal masking.** Go can disable profiling through its thread runtime
  state. This buffer uses OS signal masking so a handler cannot interrupt a
  producer that owns the lock. It blocks the supplied signals
  before lock acquisition and releases the lock before it unblocks them.
  This removes the dependency on runtime thread state but adds two mask
  operations to each write with a signal set.

- **One payload per read.** Go returns batches of records. This buffer returns
  one payload to simplify consumption. The cost is more read calls and
  position updates.

- **Rejection counter.** Go coordinates timestamped loss reports between
  producer and consumer. Here, producers increment a counter, and only the
  consumer clears it after it finds an empty ring. This removes report
  reservations and competition to claim reports. The count identifies rejected
  write calls, not lost records. Reports have no timestamp or position among
  accepted records. Continuous data can delay them without a time limit.

- **Platform waits.** Linux uses `sem_post` and `sem_wait`.
  macOS does not support unnamed semaphores, so the consumer polls every
  100 ms while the buffer is empty.

## Constraints

- The caller owns the ring storage.
  The `uint16_t length_words` argument permits a maximum payload of 512 KiB
  with the prefix. An empty ring can reject a record if the
  record and skipped tail occupy more words than its capacity.

- Writes reject records when space is not sufficient, but can wait without a
  time limit for the producer lock. The lock owner must be able to continue.
  A signal handler must return after rejection, because the interrupted
  thread can be the consumer.

- The supplied mask must include all blockable signals whose handlers write
  to this buffer. Handlers pass `NULL` and must prevent nested producer
  handlers. Unlock unblocks the supplied set, including signals blocked before
  the call. Callers that must keep the previous mask must control masking
  externally and pass `NULL`. The supplied set must stay available and
  unchanged until return. Handlers must save and restore `errno`.

- Close distinguishes an empty ring from the end of the stream. The consumer
  returns pending records and rejection reports before end-of-stream.
  The caller must stop all producers before close and stop the consumer before
  destruction. Close does not prevent subsequent writes.

- Library calls must also be safe in signal handlers.
  The producer path uses Linux/glibc's signal-safety guarantee for
  `sched_yield`.
