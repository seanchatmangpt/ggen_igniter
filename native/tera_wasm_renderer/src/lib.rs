//! WASM (wasm32-wasip1) wrapper around the real `tera` crate, exposing a
//! ptr+len marshaling ABI that a WASM host runtime (Wasmex, on the Elixir
//! side) can drive: Wasmex can call exported functions whose params/results
//! are i32/i64/f32/f64 and can read/write the instance's linear memory
//! directly, so passing template/context bytes in and reading rendered
//! output bytes back out via raw pointers into that memory is the standard,
//! robust convention for this target -- there is no richer ABI (strings,
//! structs) available across the wasm32-wasip1 export boundary itself.
//!
//! Calling convention, from the host side:
//!   1. `alloc(len)` -> ptr           -- reserve `len` bytes in linear memory
//!   2. host writes the UTF-8 template bytes at that ptr
//!   3. `alloc(len)` -> ptr           -- reserve bytes for the JSON context
//!   4. host writes the UTF-8 JSON context bytes at that ptr
//!   5. `render(template_ptr, template_len, context_ptr, context_len)` -> ptr
//!      renders (or produces an "ERROR: ..." message) into a freshly
//!      allocated output buffer and returns its pointer
//!   6. `result_len()` -> i32         -- byte length of the buffer `render`
//!      just returned (valid until the next `render`/`alloc` call)
//!   7. host reads `result_len()` bytes starting at the pointer from step 5
//!
//! Every buffer handed back to the host (from `alloc` or from `render`'s
//! return value) is intentionally leaked (`Vec::leak` / `mem::forget`): this
//! module has no `dealloc` export and no long-lived instance state beyond
//! `LAST_RESULT_LEN`, so leaking is the simple, correct choice for a
//! short-lived WASI instance that is spun up, called once or a few times,
//! and torn down by the host -- not a real leak in the long-running-process
//! sense.

use std::cell::Cell;
use std::mem;

thread_local! {
    static LAST_RESULT_LEN: Cell<i32> = Cell::new(0);
}

/// Reserve `size` bytes in this instance's linear memory and return a
/// pointer to the start of the reservation. The host writes input bytes
/// (template UTF-8, then JSON-context UTF-8) into buffers obtained this way
/// before calling `render`.
#[no_mangle]
pub extern "C" fn alloc(size: i32) -> i32 {
    if size <= 0 {
        return 0;
    }
    let mut buf: Vec<u8> = Vec::with_capacity(size as usize);
    let ptr = buf.as_mut_ptr();
    mem::forget(buf);
    ptr as i32
}

/// Byte length of the buffer most recently returned by `render`. Call this
/// immediately after `render` and before any other `alloc`/`render` call.
#[no_mangle]
pub extern "C" fn result_len() -> i32 {
    LAST_RESULT_LEN.with(|c| c.get())
}

/// Render `template` (a Tera template string) against `context` (a JSON
/// object string) using the real `tera` crate, and return a pointer to the
/// UTF-8 rendered output written into a freshly allocated buffer. On any
/// failure (invalid UTF-8 input, template parse/render error, invalid JSON
/// context), the returned buffer instead holds a UTF-8 string beginning with
/// the literal prefix `"ERROR: "` describing the failure -- callers
/// distinguish success from failure by checking that prefix, since the WASM
/// export boundary here has no room for a separate status code alongside
/// ptr+len.
///
/// # Safety
/// `template_ptr`/`context_ptr` must point at valid, readable regions of
/// this instance's linear memory of at least `template_len`/`context_len`
/// bytes respectively -- true whenever the host wrote them via buffers
/// obtained from `alloc`, per the calling convention documented on this
/// module.
#[no_mangle]
pub extern "C" fn render(
    template_ptr: i32,
    template_len: i32,
    context_ptr: i32,
    context_len: i32,
) -> i32 {
    let output = render_inner(template_ptr, template_len, context_ptr, context_len);
    write_output(output)
}

fn render_inner(template_ptr: i32, template_len: i32, context_ptr: i32, context_len: i32) -> String {
    let template_bytes = unsafe {
        std::slice::from_raw_parts(template_ptr as *const u8, template_len as usize)
    };
    let context_bytes = unsafe {
        std::slice::from_raw_parts(context_ptr as *const u8, context_len as usize)
    };

    let template = match std::str::from_utf8(template_bytes) {
        Ok(s) => s,
        Err(e) => return format!("ERROR: template is not valid UTF-8: {e}"),
    };
    let context_json = match std::str::from_utf8(context_bytes) {
        Ok(s) => s,
        Err(e) => return format!("ERROR: context is not valid UTF-8: {e}"),
    };

    let json_value: serde_json::Value = match serde_json::from_str(context_json) {
        Ok(v) => v,
        Err(e) => return format!("ERROR: context is not valid JSON: {e}"),
    };

    let tera_context = match tera::Context::from_serialize(&json_value) {
        Ok(c) => c,
        Err(e) => return format!("ERROR: context JSON is not a valid Tera context: {e}"),
    };

    match tera::Tera::one_off(template, &tera_context, false) {
        Ok(rendered) => rendered,
        Err(e) => format!("ERROR: template render failed: {e}"),
    }
}

/// Leak `s`'s bytes into a fresh buffer, record its length for `result_len`,
/// and return the buffer's pointer.
fn write_output(s: String) -> i32 {
    let bytes = s.into_bytes();
    let len = bytes.len() as i32;
    let mut buf = bytes;
    let ptr = buf.as_mut_ptr();
    mem::forget(buf);
    LAST_RESULT_LEN.with(|c| c.set(len));
    ptr as i32
}

// No native #[cfg(test)] unit tests here: this module's exported ABI
// (`alloc`/`render`/`result_len`) is designed around a single short-lived
// WASI instance owning its own linear memory, not the host test binary's
// own allocator -- calling it in-process under `cargo test` on the native
// target corrupts the test binary's own heap (observed: reliable SIGSEGV
// unrelated to template/context correctness). The real verification for
// this ABI is exercising the actual `wasm32-wasip1` build through a real
// WASM host (the `wasmtime` CLI smoke test run for this crate, and/or the
// Elixir/Wasmex end-to-end test in Phase 2) -- not a native unit test of a
// WASM-only calling convention.
