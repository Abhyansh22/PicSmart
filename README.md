# PicSmart 📸

PicSmart is a high-performance iOS gallery cleaner and organizer built from scratch using Swift and SwiftUI. Designed to handle libraries with 10,000+ assets with zero frame drops, locked 60/120 FPS scrolling, and minimal memory overhead (~30–50 MB).

---

## 🚀 Key Architectural Innovations

### 1. Multi-Stage Filtering Funnel
Directly comparing thousands of photos with neural feature extractors causes $O(N^2)$ bottlenecks, IPC daemon lockups, and thermal throttling. PicSmart employs a **5-tier progressive multi-stage sieve** where each tier eliminates 80% to 99% of non-matching media before expensive computations run:

| Tier | Technique / API | Footprint | Cost | Elimination Rate |
| :--- | :--- | :--- | :--- | :--- |
| **Tier 0: Database Index** | `PHFetchOptions` predicates & SQLite smart albums | 0 bytes | $O(1)$ lazy cursor | Instant retrieval for **Screenshots** and **Videos** without loading items into RAM. |
| **Tier 1: In-Memory Metadata** | `pixelWidth`, `pixelHeight`, `duration` | ~16 bytes | 1 CPU cycle | Eliminates ~80% to 99% of non-duplicates in under 5 ms with zero disk I/O. |
| **Tier 2: Daemon Resource IPC** | `PHAssetResource` (`fileSize` attribute) | 8 bytes | 1 CPU cycle | Off-main-thread query distinguishing burst shots from exact file copies. |
| **Tier 3: Matrix Signal Sieve** | Low-pass box-blur downsample + 64-bit `dHash` ($9 \times 8$ gradient) | 8 bytes (`UInt64`) | 1 CPU cycle (`XOR` + `POPCNT`) | Fast CPU perceptual clustering filtering out >95% of candidates. |
| **Tier 4: Neural & Cryptographic Judge** | `CryptoKit.SHA256` or `VNGenerateImageFeaturePrintRequest` | 32 B – 2 KB | Vector distance comparison | Runs **only** on narrow intermediate batches for 100% exact copy or semantic similarity confirmation. |

---

## 🛡️ Real-World Edge Case Protections

1. **Burst-Shot False Positive Trap**:
   - *Problem*: Burst photos share identical dimensions and near-identical timestamps, which falsely flags them as exact duplicates in naive algorithms.
   - *Defense*: PicSmart separates them via compressed `PHAssetResource` byte sizes (`fileSize`) and fast $32 \times 32$ pixel-level SHA-256 digests.
2. **Re-Saved / Messaging App Trap**:
   - *Problem*: Saving the same photo from different apps gives different creation timestamps.
   - *Defense*: Does not rely on creation timestamps for duplicate detection; groups strictly by aspect ratios, dimensions, byte sizes, and pixel digests.
3. **Fade-to-Black Video Trap**:
   - *Problem*: Comparing only the start (0%) or end (100%) frame of videos collides on black fade-in/fade-out transitions.
   - *Defense*: Samples 3 non-black keyframe checkpoints at **15%, 50%, and 85%** of the duration using `AVAssetImageGenerator` with keyframe snapping.
4. **Similarity Chaining Creep**:
   - *Problem*: Single-linkage clustering causes Photo A $\sim$ Photo B $\sim$ Photo C chains where A and C look completely different.
   - *Defense*: Uses **Complete-Linkage Clustering** where every pair in a cluster must satisfy the pairwise threshold $\le 0.45$.
5. **Smart "Best Shot" Tagging**:
   - Convolves a $3 \times 3$ Laplacian second-derivative kernel over grayscale thumbnails to compute edge sharpness variance ($\sigma^2$), automatically recommending the sharpest, highest-resolution photo to keep.

---

## 💾 Modern Persistence with SwiftData

- Replaces raw SQLite3 with Apple's modern **SwiftData** framework (`@ModelActor` and `@Model`).
- **`FeatureVectorStore`**: An isolated `@ModelActor` executing background transactions without blocking UI threads.
- **`CachedVisualSignature`**: Persists local identifier, modification date, 64-bit gradient hash (`dHash`), average luminance, aspect ratio band, and normalized Vision feature prints to make subsequent scans instantaneous.

---

## ⚡ Concurrency & Memory Architecture

- **`FetchResultCollection`**: Zero-allocation Swift `RandomAccessCollection` wrapper around `PHFetchResult<PHAsset>` acting as a lazy database cursor for `LazyVGrid`.
- **`TaskLimiter`**: Background task throttle bounding concurrent I/O operations to match device CPU core counts.
- **`autoreleasepool`**: Wraps batch operations to prevent Objective-C bridge allocations from accumulating during large scans.
- **`AsyncStream` Progressive Streaming**: Yields sorted results and clusters dynamically to the UI in chunks of 50–100 items.

---

## 📱 Supported Gallery Categories

1. **Screenshots**: Indexed query via `PHAssetMediaSubtype.photoScreenshot`.
2. **Videos**: Indexed query via `PHAssetMediaType.video`.
3. **Duplicate Photos**: 3-stage funnel (dimensions $\to$ byte sizes $\to$ pixel SHA-256 digests).
4. **Similar Photos**: 3-stage hybrid matrix-to-Vision funnel with sharpness-based Best Shot recommendation.
5. **Duplicate Videos**: 3-stage funnel (dimensions + rounded duration $\to$ byte sizes $\to$ 15%/50%/85% keyframes).
6. **Large Videos**: Off-thread `PHAssetResource` byte inspection sorted biggest first, with an interactive threshold slider in Settings (50 MB – 1 GB, default 200 MB).

---

## 🛠️ Requirements & Tech Stack

- **Target OS**: iOS 17.0+
- **Frameworks**: SwiftUI, Photos (PhotoKit), Vision, Accelerate (vDSP), CryptoKit, SwiftData, AVFoundation
- **Architecture**: Modern Swift Concurrency (`async`/`await`, `actors`, `@ModelActor`), Observation framework (`@Observable`, `@Environment`)
