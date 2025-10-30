RFC: Pyjamaz — a tiny Zig-powered, budget-aware, perceptual-guarded image optimizer

Status: Draft
Author: you (+ contributors)
Date: 2025-10-28
License: Apache-2.0 (recommended)

1. Problem Statement

Modern apps need small, great-looking images across devices and networks. Existing open-source tools abound (pngquant, libavif, mozjpeg, libwebp, oxipng, libvips, butteraugli/dssim), but there’s no single, cross-platform, turnkey binary that:

tries multiple formats (AVIF/WebP/JPEG/PNG),

hits a byte budget (<= N KB) automatically (target-size when supported; binary search for everything else),

enforces a perceptual guardrail (Butteraugli/DSSIM) so we never exceed visible-diff thresholds,

ships with sane defaults and an optional tiny HTTP mode, and

is fast, deterministic, and easy to automate (manifest + --json).

Pyjamaz aims to fill that gap.

2. Goals & Non-Goals
   2.1 Goals

Single static binary (Zig) for macOS (x64/arm64), Linux (x64/arm64), Windows (x64).

Batch & stream: accept folders, file lists, stdin/stdout streams.

Multi-codec search: AVIF, WebP, JPEG, PNG (quantized) candidates.

Budget targeting: respect --max-bytes or --max-kb.

Perceptual ceiling: reject candidates above --max-diff (butteraugli or dssim).

Best-passing pick: smallest file that passes perceptual threshold; tie-break by format preference.

Fast transforms: libvips for decode, resize, colorspace, orientation.

Determinism: same inputs + flags => same outputs (seeded RNG where needed).

Automation UX: JSONL manifest, machine-readable errors, exit codes.

Tiny server: optional --http :8080 that exposes one POST endpoint for optimization at the edge.

2.2 Non-Goals

Not an asset server with auth/cache invalidation (keep HTTP minimal).

Not a full DAM or pipeline orchestrator.

Not a GUI.

Not a replacement for specialist tools’ full feature sets; we wrap the happy paths.

3. User Stories

As a web dev, I point Pyjamaz at /assets/img with --max-kb 150 --max-diff 1.2 and get optimized images + a JSON manifest for my build pipeline.

As an infra engineer, I run pyjamaz --http :8080 behind a reverse proxy for on-demand optimization during a migration.

As a CI step, I enforce “no images over 200 KB unless diff <= 0.8” and fail the job if constraints aren’t met.

4. CLI Design
   pyjamaz [INPUTS ...] \
    --out ./out \
    --max-kb 150 # or --max-bytes 153600
   --max-diff 1.2 # perceptual ceiling (Butteraugli default)
   --metric butteraugli|dssim # default: butteraugli
   --formats avif,webp,jpeg,png
   --resize 1920x1080^ # libvips geometry; ^ = cover, > = only-shrink
   --sharpen auto # subtle sharpen after resize
   --icc keep|srgb|discard # default: srgb (convert to sRGB)
   --exif strip|keep # default: strip (keeps orientation as pixels)
   --concurrency auto # default: #cores
   --seed 0 # determinism
   --manifest ./out/manifest.jsonl
   --json # machine output to stdout
   --dry-run # simulate & report
   --http :8080 # tiny HTTP mode
   --cache ./cache # store candidate hashes & metrics
   --verbose

Exit codes
0 = success with at least one output
10 = budget unmet for at least one input
11 = diff ceiling unmet for all candidates
12 = decode/transform error
13 = encode error
14 = metric error

5. HTTP Mode (Optional)

POST /optimize

Headers
Content-Type: image/\* (or multipart/form-data)
X-Max-Bytes: 153600 (or X-Max-KB: 150)
X-Max-Diff: 1.2
X-Formats: avif,webp,jpeg,png (optional)

Body: raw image bytes (or multipart with file, plus optional resize, icc, exif fields)

Response: 200 OK with optimized bytes; headers include:

X-Format: avif|webp|jpeg|png

X-Bytes: N

X-Diff: f64

ETag (candidate hash)

Errors: 4xx/5xx with JSON problem detail.

This enables edge usage without turning Pyjamaz into a full image server.

6. Pipeline Overview

Ingest

Discover files or read stream.

Debounce duplicates by content hash.

Decode & Normalize

libvips: decode, apply EXIF orientation, optional resize/crop, optional sharpen, convert to sRGB, 8-bit.

Candidate Encoding (in parallel)

AVIF (libavif): if --max-bytes, use API’s target-size if available; else binary search Q.

WebP (libwebp): use size targeting (-size equivalent); else binary search Q.

JPEG (mozjpeg): binary search Q to meet size.

PNG: pngquant (palette), then optional oxipng recompression.

Perceptual Scoring

Compute diff vs original (pre-transform original or post-transform original? see §7.1) using:

Butteraugli (default); fallback to DSSIM if requested/compiled.

Selection

Discard candidates with diff > max_diff.

Pick smallest bytes; tiebreaker by --format-order.

Emit

Write output file with deterministic name (content hash + extension, or original stem).

Write manifest line (JSONL).

If --json, also print an event per file to stdout.

7. Perceptual Metrics & Comparisons
   7.1 What to compare against?

Default: compare post-transform original vs post-transform candidate.
Rationale: users judge quality on the resized version they ship. Steps:

Decode original → normalize/resize → baseline frame

Encode to candidate → decode candidate → normalize/resize (same) → candidate frame

Run metric on baseline vs candidate frame.

Option --diff-against original: compare vs full-resolution original if desired; slower and sometimes misleading for resized outputs.

7.2 Threshold semantics

--max-diff expects a metric-native number:

Butteraugli: lower is better; ~1.0 ≈ “visually near-lossless” for many images (you'll tune defaults).

DSSIM: 0..∞ where 0 is identical; common gates: <= 0.015–0.05.

7.3 Speed knobs

--metric-subsample 2 (optional) to speed scoring on very large images; document the tradeoff.

8. Quality-to-Size Search
   8.1 When encoders support target size

AVIF: use libavif’s target-size if present; else our binary search over quantizer (Y/A).

WebP: use libwebp’s target size; else search q.

8.2 Binary search (general case)

Inputs: max_bytes, q_min, q_max, max_iters=7, tolerance=1%.

At each step:

Encode at q_mid.

If size > budget → increase compression (lower quality); else try improving quality (raise q).

Gather 2–3 promising candidates around the budget for the perceptual check (not just the final boundary), because a slightly larger file might pass diff while the boundary one fails.

8.3 Dual-constraint check

The final pick must satisfy both:

bytes <= max_bytes

diff <= max_diff

If none pass:

Return the best diff candidate (lowest diff) and emit a policy violation in the manifest; exit code 10/11 depending on which constraint failed.

9. Metadata, ICC, and Color

EXIF: default strip, but bake orientation into pixels during normalization.

ICC: default srgb (convert); keep to embed original profile (may affect size).

Alpha:

PNG/AVIF/WebP handle alpha.

JPEG candidates are skipped if source has non-opaque alpha (unless --flatten "#RRGGBB" is set).

10. File Naming, Output, and Manifest
    10.1 Output naming

Default: <stem>.<fmt> into --out.

Option: --content-hash-names → <stem>.<short-hash>.<fmt>.

--preserve-subdirs mirrors input tree.

10.2 Manifest (JSONL)

Each line represents one input:

{
"input": "images/hero.png",
"output": "out/hero.avif",
"bytes": 142381,
"format": "avif",
"diff_metric": "butteraugli",
"diff_value": 0.93,
"budget_bytes": 153600,
"max_diff": 1.2,
"passed": true,
"alternates": [
{"format":"webp","bytes":151202,"diff":1.01,"passed":true},
{"format":"jpeg","bytes":154900,"diff":0.85,"passed":false,"reason":"over_budget"}
],
"timings_ms": {
"decode": 8,
"transform": 4,
"encode_total": 31,
"metrics": 6
},
"warnings": []
}

11. Concurrency, Caching, and Determinism

Thread pool sized to logical cores; per-image work scheduled as a unit to reduce thrash.

Stage parallelism: candidates (formats) per image run in parallel; cap with --concurrency.

Cache:

Key: (baseline_hash, encoder_id, params)

Store: encoded bytes + diff value.

Avoid recomputing during experiments and HTTP hot paths.

Determinism:

Seed any stochastic components (--seed).

Pin library versions and codec options.

12. Dependencies

Zig: system language, cross-compilation, small static binaries.

libvips: decode/resize/colorspace/orientation.

libavif: AVIF encode/decode (with target size API if available).

libwebp: WebP encode/decode (size targeting).

mozjpeg: JPEG encode with trellis/optimize.

pngquant + oxipng: palettization + recompression.

butteraugli (default) and/or dssim: perceptual metrics.

Optional: zlib/deflate backends for oxipng.

Bundle as static (where licenses allow) or ship as dynamically linked with a tiny bootstrap. Favor vendored, reproducible builds.

Licensing compliance:

Keep third-party notices; generate THIRD_PARTY_NOTICES.md.

Provide a --licenses flag to print versions and licenses at runtime.

13. Build & Packaging

Zig build.zig orchestrates C dependencies (cmake where needed).

Targets: x86_64-linux-musl, aarch64-linux-musl, x86_64-windows-gnu, aarch64-macos, x86_64-macos.

Releases: attach static binaries + checksums + SBOM (CycloneDX) to GitHub Releases.

Docker: scratch or distroless image for HTTP mode.

14. Security & Sandboxing

Refuse to follow symlinks outside input root unless --allow-symlinks.

Limit memory via --mem-limit (soft), and safeguard against decompression bombs.

HTTP mode:

Max payload size (--http-max-bytes).

Timeout & concurrency caps.

No directory traversal; no write access except ephemeral cache.

Optional allowlist of MIME types.

15. Observability

--json emits JSONL progress events.

--verbose prints human logs.

--trace ./trace.jsonl adds per-stage timing and decision logs.

Prometheus (HTTP mode): /metrics (optional) for op counts, latencies, cache hit rate.

16. Edge Cases & Policy

Animated inputs: initial MVP: treat as still (first frame). Option --animate copy|first|error.

CMYK JPEGs: libvips converts to sRGB; warn if profile missing.

Tiny icons: skip heavy codecs under --min-px (e.g., < 20×20) to avoid bloat.

Text/line art: allow --prefer-png-for-lineart heuristic (edge density).

Alpha with JPEG: require --flatten to consider JPEG; else skip.

17. Heuristics (Sane Defaults)

Format order: avif,webp,jpeg,png

AVIF: speed medium, 4:2:0 default, enable sharpness; try target-size if present.

WebP: use target bytes; else q-search 80–95 first.

JPEG (mozjpeg): start 80–92; optimize scans; trellis on; progressive on.

PNG: pngquant --speed 2 --quality 60-90, then oxipng -o 3.

Butteraugli: default --max-diff 1.2 (tunable).

Resize: only shrink by default (> geometry).

18. Pseudocode (High-Level, Zig-style)
    pub fn optimizeOne(alloc: \*Allocator, job: Job) !Result {
    const baseline = try normalizeWithVips(alloc, job.input, job.transforms);
    var candidates = std.ArrayList(Candidate).init(alloc);

        const formats = job.formats; // avif, webp, jpeg, png
        var wg = WaitGroup{};
        for (formats) |fmt| {
            wg.add(1);
            spawn encodeCandidate(fmt, baseline, job, &candidates, &wg);
        }
        wg.wait();

        // Score candidates
        for (candidates.items) |*cand| {
            cand.diff = try perceptualDiff(job.metric, baseline, cand.bytes);
            cand.passed = cand.bytes.len <= job.max_bytes and cand.diff <= job.max_diff;
        }

        // Choose
        const pick = chooseBest(candidates.items, job.format_preference);
        if (pick == null) return error.NoPassingCandidate;

        try writeOutput(job.out_dir, job.naming, pick.?);
        return resultFrom(pick.? , candidates.items);

    }

19. Testing & Benchmarks

Golden corpus (~200 images):

Photographic, UI/text, line art, alpha, HDR→SDR, noisy dark scenes.

Snapshots:

Verify determinism (hash of outputs).

Quality gates:

Assert diff <= max_diff for defaults across corpus.

Perf:

Report median/95p for per-image latency with concurrency.

Budget adherence:

Assert bytes <= max_bytes for each.

CI matrix across OS/arch; nightly corpus test; publish metrics table to README.

20. Roadmap

MVP (v0.1):

CLI, libvips normalization, AVIF/WebP/JPEG/PNG candidates

Target-size & binary search

Butteraugli scoring

Selection + manifest

Basic HTTP mode

v0.2:

Caching layer, DSSIM option, Prometheus, SBOM, Docker image

v0.3:

Animation support (WebP/AVIF), content-aware defaults (line art heuristic)

v1.0:

Stabilize flags, full docs, reproducible release pipeline

21. Open Questions

Exact Butteraugli defaults per content type—ship a conservative global default first.

HDR pipelines (PQ/HLG) → likely out of MVP; require careful tone mapping.

License mixing: ensure static linking is permissible for chosen builds (else ship minimal shared libs).

22. Suggested Project Names (with a z)

Pick your vibe:

Pyjamaz (what this RFC uses; clear on purpose)

Zqueeze (fun, evokes compression)

Zoptic (optimal + z; “optics” pun)

Zight (light + z; “make images light”)

Zimage (straightforward)

Zpress (express + compress)

Zharp (sharp + z; nod to libvips/sharp)

Zlim (slim with z)

Zigil (Zig + sigil; quirky)

VizZig (visual + Zig; playful)

23. Example Sessions
    23.1 Batch
    pyjamaz ./images --out ./dist/img \
     --max-kb 150 --max-diff 1.2 --formats avif,webp,jpeg,png \
     --resize 1920x1080> --exif strip --icc srgb \
     --manifest ./dist/manifest.jsonl --json --concurrency auto

23.2 Fail the build on violations
pyjamaz ./images --out ./dist --max-kb 200 --max-diff 1.0 --json || exit 1

23.3 HTTP edge
pyjamaz --http :8080 --concurrency 8 --cache /tmp/pyjamaz

# curl -H 'X-Max-KB: 150' --data-binary @hero.png http://localhost:8080/optimize > hero.avif

24. Minimal Config File (TOML)
    out = "dist/img"
    max_kb = 150
    max_diff = 1.2
    formats = ["avif","webp","jpeg","png"]
    resize = "1920x1080>"
    icc = "srgb"
    exif = "strip"
    concurrency = "auto"
    manifest = "dist/manifest.jsonl"

Run with: pyjamaz --config pyjamaz.toml

25. Developer Notes (FFI)

Use Zig’s C interop for libvips/libavif/libwebp/mozjpeg/pngquant/oxipng.

Wrap each codec with a uniform Encoder trait-like interface:

prepare(baseline, opts) -> Capability

encodeWithQuality(q|params) -> Candidate

encodeToSize(max_bytes) -> Candidate | null

Metrics adapter interface:

score(baseline, candidate) -> f64

Guard codec threads; some libraries aren’t fully thread-safe unless globally init’d once.

26. Community & Governance

Contributions: CLA-less, DCO sign-off.

Issue labels: good first issue, backend, codec, metric, perf, http, docs.

Reproducible example bundles for bugs (input, flags, expected).

27. Implementation Notes & Extensions

27.1 Conformance Testing Strategy

Conformance tests validate Pyjamaz against known-good image optimization scenarios.

Test Suite Sources:
- **Kodak Image Suite**: 24 photographic images, standard quality baseline
- **PngSuite**: Comprehensive PNG edge cases (interlacing, bit depths, transparency)
- **WebP Gallery**: Google's reference WebP images
- **TESTIMAGES**: Standard test images (Lena, Baboon, Peppers)
- **Synthetic**: Generated images (gradients, patterns, solid colors)

Test Data Management:
- Download via `docs/scripts/download_testdata.sh` (not committed to repo)
- CI downloads on-demand (cached between runs)
- Developers opt-in (run script manually)
- Total size: ~150 MB (acceptable for opt-in)

Conformance Validation:
1. **Correctness**: Output is valid image (decodable)
2. **Size**: Output <= input size OR within 5% (for tiny images)
3. **Quality**: Perceptual diff <= max_diff (once metrics implemented)
4. **Determinism**: Same input + flags → same output hash
5. **Performance**: Optimization completes within reasonable time

Exit Codes:
- 0: All tests pass
- 1: At least one test fails
- Exit immediately on first failure (fail-fast for CI)

27.2 Tiger Style Compliance Checklist

Every Zig module must satisfy:

✅ **Safety**:
- 2+ assertions per function (pre/post-conditions, invariants)
- Bounded loops (explicit max iterations)
- No `catch unreachable` without proof
- Explicit error handling (propagate or handle, never silence)

✅ **Types**:
- Use `u32` for counts/indices (not `usize` unless memory addresses)
- Explicit types (no implicit `var` where avoidable)
- Integer overflow checks enabled

✅ **Functions**:
- ≤70 lines per function (extract helpers if needed)
- Single responsibility
- Clear, descriptive names (no abbreviations)
- Doc comments for all public functions

✅ **Memory**:
- Explicit allocator passing (no global state)
- RAII patterns (defer cleanup)
- Test with `testing.allocator` (leak detection)

✅ **Performance**:
- Document time complexity (Big-O)
- Back-of-envelope calculations for limits
- No unbounded allocations

27.3 Codec-Specific Considerations

**JPEG (mozjpeg)**:
- Trellis quantization: ON (better compression)
- Progressive encoding: ON (better web experience)
- Optimize scans: ON
- Default quality search: 80-92 (typical web sweet spot)
- Skip if input has non-opaque alpha (unless --flatten)

**PNG (pngquant + oxipng)**:
- pngquant: --speed 2 --quality 60-90 (balance speed/quality)
- oxipng: -o 3 (good compression without extreme slowdown)
- Prefer for: line art, text, icons, images with alpha
- Use palette quantization only if >256 colors (else full color)

**WebP**:
- Use target-size API if present (libwebp >= 1.2)
- Default quality search: 80-95
- Alpha: always supported
- Lossless mode: consider for line art (future enhancement)

**AVIF**:
- Default speed: medium (balance encoding time vs size)
- Chroma subsampling: 4:2:0 (standard, good compression)
- Alpha: always supported
- Timeout: 30s per image (prevent slow encodes from hanging)
- Consider skipping for very small images (<20x20) - overhead not worth it

27.4 Build System Strategy

**Dependency Management**:
- Prefer static linking (single binary goal)
- Vendor C libraries where licenses permit (Apache-2.0, MIT, BSD)
- Document dependencies in build.zig with version pins
- Use Zig's C interop (no need for pkg-config at runtime)

**Cross-Compilation**:
- Zig's native cross-compilation for all targets
- Test on actual hardware (VMs for Linux/Windows, native macOS)
- GitHub Actions matrix: macOS (x64/arm64), Linux (x64/arm64), Windows (x64)

**THIRD_PARTY_NOTICES**:
- Auto-generate from build.zig at compile time
- Include library name, version, license, copyright
- Embed in binary (accessible via --licenses flag)

27.5 Performance Optimization Priorities

**Phase 1 (MVP)**: Correctness over speed
- Focus on getting pipeline right
- Basic parallelism (per-image tasks)
- Acceptable: 1-2 seconds per image

**Phase 2 (0.2.0)**: Optimize hot paths
- Profile with real images (Kodak suite)
- Optimize perceptual metric computation (often slowest)
- Parallel candidate encoding (all formats at once)
- Target: <500ms per image on modern hardware

**Phase 3 (0.3.0)**: Cache & avoid work
- Cache encoded candidates by (baseline_hash, params)
- Cache perceptual diff scores
- Skip redundant work for identical inputs
- Target: <100ms on cache hit

**Phase 4 (1.0.0)**: Advanced optimizations
- Consider SIMD for metrics (if bottleneck)
- Multi-pass optimization (refine best candidate)
- Investigate GPU encoding (future research)

27.6 Testing Philosophy

**Unit Tests (>80% coverage)**:
- Test every public function in isolation
- Use `testing.allocator` (catch leaks)
- Property-based testing for parsers (fuzz inputs)
- Edge cases: empty, maximum, invalid

**Integration Tests**:
- End-to-end workflows (file → optimized file)
- CLI flag combinations
- Error scenarios (bad input, disk full, OOM)

**Conformance Tests**:
- Real-world image corpus
- Validate against known-good behavior
- Regression detection (golden outputs)

**Benchmark Tests**:
- Measure absolute performance (not just relative)
- Track over time (detect regressions)
- Document on real hardware (not just CI)

**Security Tests**:
- Decompression bombs
- Symlink traversal
- Oversized inputs
- Malformed images (fuzzing)

27.7 Documentation Standards

Every doc file must answer:
- **README.md**: What is this? (for users discovering project)
- **CLAUDE.md**: How is this structured? (navigation hub)
- **docs/TODO.md**: What's the plan? (roadmap, tasks)
- **docs/ARCHITECTURE.md**: How does it work? (system design)
- **docs/CONTRIBUTING.md**: How can I help? (for contributors)
- **docs/RFC.md**: Why these decisions? (design rationale)
- **src/CLAUDE.md**: How do I implement? (patterns, examples)

Code comments must explain **WHY**, not WHAT:
```zig
// ✅ GOOD: Explains reasoning
// Use u32 instead of usize to ensure deterministic output on 32/64-bit platforms
const max_iterations: u32 = 7;

// ❌ BAD: Restates the obvious
// Set max iterations to 7
const max_iterations: u32 = 7;
```

27.8 Release Checklist

Before tagging a release:
- [ ] All tests pass (unit, integration, conformance)
- [ ] `zig fmt` applied to entire codebase
- [ ] CHANGELOG.md updated with all changes
- [ ] Version bumped in build.zig
- [ ] Cross-platform binaries built and tested
- [ ] SBOM generated (CycloneDX)
- [ ] Checksums generated (SHA256)
- [ ] GitHub Release created with binaries + checksums + SBOM
- [ ] Documentation updated (README, installation instructions)
- [ ] Announcement drafted (blog post, social media)

27.9 Open Research Questions

**HDR Support**:
- PQ/HLG tone mapping is complex; defer to post-1.0
- Requires careful color science (not just codec support)
- Consider libplacebo integration for tone mapping

**GPU Encoding**:
- NVIDIA/AMD have hardware JPEG/H.265 encoders
- Research: Can we leverage for AVIF encoding?
- Complexity vs speedup tradeoff (may not be worth it for v1.0)

**WebAssembly Target**:
- Zig supports WASM, but codec libraries need porting
- Browser use case: client-side optimization before upload
- Future: pyjamaz.wasm + JS bindings

**Animated GIF → WebP/AVIF**:
- Frame timing preservation is non-trivial
- Different loop semantics between formats
- MVP: extract first frame; full support in 0.3.0
