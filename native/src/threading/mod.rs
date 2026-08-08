//! Bounded intra-operation parallelism for pixel processing stages.
//!
//! The shared pool prevents each image job from creating its own OS threads.
//! Metadata inspection intentionally does not use this module.

use std::fmt;
use std::sync::OnceLock;

use rayon::prelude::*;
use rayon::{ThreadPool, ThreadPoolBuildError, ThreadPoolBuilder};

const DEFAULT_MAX_THREADS: usize = 8;
const DEFAULT_MIN_PARALLEL_PIXELS: usize = 1_048_576;
const TASKS_PER_THREAD: usize = 2;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ThreadingPolicy {
    /// Hard cap for threads used by one shared native processing pool.
    pub max_threads: usize,
    /// Images below this pixel count remain single-threaded.
    pub min_parallel_pixels: usize,
}

impl Default for ThreadingPolicy {
    fn default() -> Self {
        let available = std::thread::available_parallelism()
            .map(usize::from)
            .unwrap_or(1);
        Self {
            max_threads: available.min(DEFAULT_MAX_THREADS).max(1),
            min_parallel_pixels: DEFAULT_MIN_PARALLEL_PIXELS,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ExecutionMode {
    Sequential,
    Parallel { threads: usize },
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ThreadingError {
    InvalidRowLayout,
}

impl fmt::Display for ThreadingError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidRowLayout => {
                formatter.write_str("buffer length must contain complete non-empty rows")
            }
        }
    }
}

impl std::error::Error for ThreadingError {}

#[derive(Debug)]
pub enum ThreadingInitError {
    ZeroThreads,
    Pool(ThreadPoolBuildError),
}

impl fmt::Display for ThreadingInitError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::ZeroThreads => formatter.write_str("thread count must be non-zero"),
            Self::Pool(error) => write!(formatter, "failed to create processing pool: {error}"),
        }
    }
}

impl std::error::Error for ThreadingInitError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::ZeroThreads => None,
            Self::Pool(error) => Some(error),
        }
    }
}

impl From<ThreadPoolBuildError> for ThreadingInitError {
    fn from(error: ThreadPoolBuildError) -> Self {
        Self::Pool(error)
    }
}

/// A reusable pool for parallel sections inside one decode/transform/encode
/// operation. Multiple image jobs share the same bounded pool.
pub struct ParallelExecutor {
    policy: ThreadingPolicy,
    pool: ThreadPool,
}

impl ParallelExecutor {
    pub fn new(policy: ThreadingPolicy) -> Result<Self, ThreadingInitError> {
        if policy.max_threads == 0 {
            return Err(ThreadingInitError::ZeroThreads);
        }
        let pool = ThreadPoolBuilder::new()
            .num_threads(policy.max_threads)
            .thread_name(|index| format!("file-image-cropper-{index}"))
            .build()?;
        Ok(Self { policy, pool })
    }

    pub fn policy(&self) -> ThreadingPolicy {
        self.policy
    }

    pub fn thread_count(&self) -> usize {
        self.pool.current_num_threads()
    }

    /// Processes disjoint row bands. `pixel_count` drives the parallelism
    /// threshold independently of bytes-per-pixel or element type.
    pub fn for_each_row_band_mut<T, F>(
        &self,
        buffer: &mut [T],
        elements_per_row: usize,
        pixel_count: usize,
        operation: F,
    ) -> Result<ExecutionMode, ThreadingError>
    where
        T: Send,
        F: Fn(&mut [T], usize) + Sync + Send,
    {
        if elements_per_row == 0 || buffer.len() % elements_per_row != 0 {
            return Err(ThreadingError::InvalidRowLayout);
        }
        let rows = buffer.len() / elements_per_row;
        if rows == 0 {
            return Ok(ExecutionMode::Sequential);
        }

        let threads = self.thread_count().min(rows);
        let nested_parallel_section = rayon::current_thread_index().is_some();
        if threads < 2 || pixel_count < self.policy.min_parallel_pixels || nested_parallel_section {
            operation(buffer, 0);
            return Ok(ExecutionMode::Sequential);
        }

        let target_tasks = threads * TASKS_PER_THREAD;
        let rows_per_band = rows.div_ceil(target_tasks).max(1);
        let elements_per_band = rows_per_band * elements_per_row;
        self.pool.install(|| {
            buffer
                .par_chunks_mut(elements_per_band)
                .enumerate()
                .for_each(|(band_index, band)| {
                    operation(band, band_index * rows_per_band);
                });
        });
        Ok(ExecutionMode::Parallel { threads })
    }
}

static SHARED_EXECUTOR: OnceLock<Option<ParallelExecutor>> = OnceLock::new();

/// Returns the process-wide bounded executor. If worker creation fails, pixel
/// stages can safely fall back to their sequential implementation.
pub fn shared_executor() -> Option<&'static ParallelExecutor> {
    SHARED_EXECUTOR
        .get_or_init(|| ParallelExecutor::new(ThreadingPolicy::default()).ok())
        .as_ref()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn small_buffers_stay_sequential() {
        let executor = ParallelExecutor::new(ThreadingPolicy {
            max_threads: 2,
            min_parallel_pixels: 100,
        })
        .unwrap();
        let mut output = vec![0_u8; 40];
        let mode = executor
            .for_each_row_band_mut(&mut output, 4, 10, |band, first_row| {
                for (index, value) in band.iter_mut().enumerate() {
                    *value = (first_row * 4 + index) as u8;
                }
            })
            .unwrap();
        assert_eq!(mode, ExecutionMode::Sequential);
        assert_eq!(output, (0_u8..40).collect::<Vec<_>>());
    }

    #[test]
    fn parallel_bands_are_disjoint_and_complete() {
        let executor = ParallelExecutor::new(ThreadingPolicy {
            max_threads: 2,
            min_parallel_pixels: 1,
        })
        .unwrap();
        let mut output = vec![0_usize; 4_000];
        let mode = executor
            .for_each_row_band_mut(&mut output, 4, 1_000, |band, first_row| {
                for (index, value) in band.iter_mut().enumerate() {
                    *value = first_row * 4 + index + 1;
                }
            })
            .unwrap();
        assert_eq!(mode, ExecutionMode::Parallel { threads: 2 });
        assert_eq!(output, (1_usize..=4_000).collect::<Vec<_>>());
    }

    #[test]
    fn rejects_partial_rows() {
        let executor = ParallelExecutor::new(ThreadingPolicy::default()).unwrap();
        let mut output = [0_u8; 7];
        assert_eq!(
            executor.for_each_row_band_mut(&mut output, 4, 7, |_, _| {}),
            Err(ThreadingError::InvalidRowLayout)
        );
    }

    #[test]
    fn rejects_zero_thread_configuration() {
        assert!(matches!(
            ParallelExecutor::new(ThreadingPolicy {
                max_threads: 0,
                min_parallel_pixels: 1,
            }),
            Err(ThreadingInitError::ZeroThreads)
        ));
    }

    #[test]
    fn nested_parallel_sections_fall_back_to_sequential() {
        let executor = ParallelExecutor::new(ThreadingPolicy {
            max_threads: 2,
            min_parallel_pixels: 1,
        })
        .unwrap();
        executor.pool.install(|| {
            let mut output = [0_u8; 8];
            let mode = executor
                .for_each_row_band_mut(&mut output, 2, 4, |band, _| band.fill(1))
                .unwrap();
            assert_eq!(mode, ExecutionMode::Sequential);
            assert_eq!(output, [1; 8]);
        });
    }
}
