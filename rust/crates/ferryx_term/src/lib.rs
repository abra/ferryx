//! The integrated terminal's shell.
//!
//! A [`Session`] runs the user's shell in a pseudo-terminal (`portable-pty`:
//! openpty on Unix, ConPTY on Windows) and reports through one listener:
//! output in batches with flow control, the shell's state (at its prompt or
//! running a program, its folder) when it changes, and its end. The
//! terminal emulation itself is the interface's.

mod batch;
mod error;
pub mod process;
mod pty_io;
mod session;
pub mod shell;

pub use error::{TermError, TermErrorKind};
pub use session::{Event, Listener, Session, SessionConfig, ShellState, BATCH_LIMIT, CREDITS, WINDOW};
