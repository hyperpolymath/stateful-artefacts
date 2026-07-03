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
#include <stddef.h>

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

/*
 * Artefact state record (v0).
 * Spec: docs/spec/ARTEFACT-STATE-RECORD.adoc. Enum codes are stable and shared
 * with src/core/record.zig and src/interface/Abi/Record.idr.
 */

typedef enum {
    STATEFUL_ARTEFACTS_KIND_BINARY = 0,
    STATEFUL_ARTEFACTS_KIND_CONTAINER = 1,
    STATEFUL_ARTEFACTS_KIND_DATASET = 2,
    STATEFUL_ARTEFACTS_KIND_DOCUMENT = 3,
    STATEFUL_ARTEFACTS_KIND_OTHER = 4
} stateful_artefacts_kind_t;

typedef enum {
    STATEFUL_ARTEFACTS_PHASE_DRAFT = 0,
    STATEFUL_ARTEFACTS_PHASE_BUILT = 1,
    STATEFUL_ARTEFACTS_PHASE_RELEASED = 2,
    STATEFUL_ARTEFACTS_PHASE_SUPERSEDED = 3,
    STATEFUL_ARTEFACTS_PHASE_WITHDRAWN = 4
} stateful_artefacts_phase_t;

typedef enum {
    STATEFUL_ARTEFACTS_VERIFICATION_UNVERIFIED = 0,
    STATEFUL_ARTEFACTS_VERIFICATION_VERIFIED = 1,
    STATEFUL_ARTEFACTS_VERIFICATION_REJECTED = 2
} stateful_artefacts_verification_t;

/* Opaque artefact-state-record handle. */
typedef struct stateful_artefacts_record stateful_artefacts_record;

/* Create/destroy. new() returns NULL on failure (null/over-long id, bad kind). */
stateful_artefacts_record *stateful_artefacts_record_new(const char *id, int kind);
void stateful_artefacts_record_free(stateful_artefacts_record *rec);

/* Field accessors. Return the enum code, or -1 on NULL. */
int stateful_artefacts_record_phase(stateful_artefacts_record *rec);
int stateful_artefacts_record_verification(stateful_artefacts_record *rec);

/* Provenance. source_ref/produced_by may be NULL (left unset). */
int stateful_artefacts_record_set_provenance(stateful_artefacts_record *rec,
                                             const char *source_ref,
                                             const char *produced_by,
                                             int64_t timestamp);

/* State machines. Illegal transitions return invalid_param and change nothing. */
int stateful_artefacts_record_advance_phase(stateful_artefacts_record *rec, int to);
int stateful_artefacts_record_set_verification(stateful_artefacts_record *rec, int to);
/* The only path back to UNVERIFIED (explicit re-assessment). */
int stateful_artefacts_record_reopen_verification(stateful_artefacts_record *rec);

/* Serialize (v0 key=value form) into buf; returns bytes written or -1. */
int stateful_artefacts_record_serialize(stateful_artefacts_record *rec,
                                        unsigned char *buf, size_t len);

#ifdef __cplusplus
}
#endif

#endif /* STATEFUL_ARTEFACTS_H */
