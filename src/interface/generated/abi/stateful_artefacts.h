/* SPDX-License-Identifier: MPL-2.0 */
/* Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk> */
/*
 * stateful-artefacts — C ABI
 *
 * Hand-maintained C-consumer contract for libstateful_artefacts. It mirrors,
 * symbol for symbol, the `export fn stateful_artefacts_*` functions in
 * src/interface/ffi/src/main.zig and the `%foreign` bindings in
 * src/interface/Abi/Foreign.idr. Modern Zig/Idris2 do not emit a usable C
 * header automatically; keep these three in lock-step when changing an export
 * (tests/aspect_tests.sh checks Idris2<->Zig symbol parity).
 */

#ifndef STATEFUL_ARTEFACTS_H
#define STATEFUL_ARTEFACTS_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

/* Result codes (ADR-003 canon — identical to the Zig and Idris2 sides). */
typedef enum {
    STATEFUL_ARTEFACTS_OK = 0,
    STATEFUL_ARTEFACTS_ERROR = 1,
    STATEFUL_ARTEFACTS_INVALID_PARAM = 2,
    STATEFUL_ARTEFACTS_OUT_OF_MEMORY = 3,
    STATEFUL_ARTEFACTS_NULL_POINTER = 4
} stateful_artefacts_result_t;

/* Opaque library handle. */
typedef struct stateful_artefacts_handle stateful_artefacts_handle;

/* Callback type (C ABI). */
typedef uint32_t (*stateful_artefacts_callback)(uint64_t, uint32_t);

/* Lifecycle. */
stateful_artefacts_handle *stateful_artefacts_init(void);
void stateful_artefacts_free(stateful_artefacts_handle *handle);

/* Core operations. Return a stateful_artefacts_result_t value (as int). */
int stateful_artefacts_process(stateful_artefacts_handle *handle, uint32_t input);
int stateful_artefacts_process_array(stateful_artefacts_handle *handle,
                                     const uint8_t *buffer, uint32_t len);

/* Strings. get_string returns a library-allocated, NUL-terminated string that
 * the caller must release with free_string (or NULL on failure). */
const char *stateful_artefacts_get_string(stateful_artefacts_handle *handle);
void stateful_artefacts_free_string(const char *str);

/* Error reporting. Returns static storage (do not free) or NULL if no error. */
const char *stateful_artefacts_last_error(void);

/* Version and build info. Both return static storage (do not free). */
const char *stateful_artefacts_version(void);
const char *stateful_artefacts_build_info(void);

/* Callbacks. */
int stateful_artefacts_register_callback(stateful_artefacts_handle *handle,
                                         stateful_artefacts_callback callback);

/* Utilities. Returns 1 if the handle is initialized, 0 otherwise. */
uint32_t stateful_artefacts_is_initialized(stateful_artefacts_handle *handle);

#ifdef __cplusplus
}
#endif

#endif /* STATEFUL_ARTEFACTS_H */
