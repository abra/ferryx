//! The shell's output gathered into batches, so the interface gets one
//! event per frame or so however many reads the bytes came in.

use std::time::{Duration, Instant};

use crossbeam_channel::{Receiver, RecvTimeoutError};

/// What [`Batcher::next`] found.
#[derive(Debug, PartialEq, Eq)]
pub enum Next {
    /// Bytes to send, `limit` at most.
    Batch(Vec<u8>),
    /// Nothing came within the wait.
    Idle,
    /// The reader has stopped and everything it read has been sent.
    Closed,
}

/// Gathers chunks from the reader into batches of at most `limit` bytes,
/// one per `window` at most: a keystroke's echo after a pause goes at once,
/// a flood of output goes `window` apart (rate, not delay).
pub struct Batcher {
    window: Duration,
    limit: usize,
    pending: Vec<u8>,
    last_sent: Option<Instant>,
}

impl Batcher {
    pub fn new(window: Duration, limit: usize) -> Batcher {
        Batcher { window, limit: limit.max(1), pending: Vec::new(), last_sent: None }
    }

    /// The next batch: waits up to `idle` for the first chunk, then takes
    /// what comes until the window since the last batch has passed or the
    /// batch is full. Bytes over the limit wait for the next call.
    pub fn next(&mut self, rx: &Receiver<Vec<u8>>, idle: Duration) -> Next {
        if self.pending.is_empty() {
            match rx.recv_timeout(idle) {
                Ok(chunk) => self.pending = chunk,
                Err(RecvTimeoutError::Timeout) => return Next::Idle,
                Err(RecvTimeoutError::Disconnected) => return Next::Closed,
            }
        }
        let now = Instant::now();
        let deadline = self.last_sent.map_or(now, |sent| (sent + self.window).max(now));
        while self.pending.len() < self.limit {
            match rx.recv_deadline(deadline) {
                Ok(chunk) => self.pending.extend_from_slice(&chunk),
                // The closing is seen by the next call, after this batch.
                Err(_) => break,
            }
        }
        let batch = if self.pending.len() > self.limit {
            let rest = self.pending.split_off(self.limit);
            std::mem::replace(&mut self.pending, rest)
        } else {
            std::mem::take(&mut self.pending)
        };
        self.last_sent = Some(Instant::now());
        Next::Batch(batch)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crossbeam_channel::unbounded;

    #[test]
    fn many_small_chunks_make_few_batches() {
        let (tx, rx) = unbounded();
        for _ in 0..10_000 {
            tx.send(vec![b'y', b'\n']).unwrap();
        }
        drop(tx);
        let mut batcher = Batcher::new(Duration::from_millis(8), 64 * 1024);
        let mut batches = Vec::new();
        loop {
            match batcher.next(&rx, Duration::from_millis(100)) {
                Next::Batch(bytes) => batches.push(bytes),
                Next::Closed => break,
                Next::Idle => panic!("idle with bytes waiting"),
            }
        }
        assert_eq!(batches.iter().map(Vec::len).sum::<usize>(), 20_000);
        assert!(batches.len() <= 2, "{} batches", batches.len());
    }

    #[test]
    fn a_batch_never_exceeds_the_limit_and_keeps_the_order() {
        let (tx, rx) = unbounded();
        tx.send((0..=255u8).collect()).unwrap();
        tx.send((0..=255u8).collect()).unwrap();
        drop(tx);
        let mut batcher = Batcher::new(Duration::from_millis(1), 100);
        let mut all = Vec::new();
        while let Next::Batch(bytes) = batcher.next(&rx, Duration::from_millis(10)) {
            assert!(bytes.len() <= 100);
            all.extend(bytes);
        }
        let expected: Vec<u8> = (0..=255u8).chain(0..=255u8).collect();
        assert_eq!(all, expected);
    }

    #[test]
    fn idle_when_nothing_comes_and_closed_when_the_reader_stops() {
        let (tx, rx) = unbounded::<Vec<u8>>();
        let mut batcher = Batcher::new(Duration::from_millis(8), 1024);
        assert_eq!(batcher.next(&rx, Duration::from_millis(5)), Next::Idle);
        tx.send(b"tail".to_vec()).unwrap();
        drop(tx);
        assert_eq!(batcher.next(&rx, Duration::from_millis(5)), Next::Batch(b"tail".to_vec()));
        assert_eq!(batcher.next(&rx, Duration::from_millis(5)), Next::Closed);
    }

    #[test]
    fn an_echo_after_a_pause_goes_at_once() {
        let (tx, rx) = unbounded();
        let mut batcher = Batcher::new(Duration::from_millis(500), 1024);
        tx.send(b"a".to_vec()).unwrap();
        let started = Instant::now();
        assert_eq!(batcher.next(&rx, Duration::from_millis(5)), Next::Batch(b"a".to_vec()));
        assert!(started.elapsed() < Duration::from_millis(100));
    }

    #[test]
    fn a_flood_goes_a_window_apart() {
        let (tx, rx) = unbounded();
        let window = Duration::from_millis(30);
        let mut batcher = Batcher::new(window, 1 << 20);
        tx.send(b"first".to_vec()).unwrap();
        assert!(matches!(batcher.next(&rx, window), Next::Batch(_)));
        let sent = Instant::now();
        tx.send(b"second".to_vec()).unwrap();
        assert_eq!(batcher.next(&rx, window), Next::Batch(b"second".to_vec()));
        assert!(sent.elapsed() >= window - Duration::from_millis(5));
    }
}
