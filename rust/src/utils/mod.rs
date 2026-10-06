pub mod error;
pub mod cloudflare_ranges;

pub use error::{CoreError, Result};
pub use cloudflare_ranges::CloudflareDetector;
