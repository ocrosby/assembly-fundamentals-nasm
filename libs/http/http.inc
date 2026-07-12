; http.inc — constants and struct offsets for libhttp.
;
; Every symbol here is either a compile-time enum (HTTP_VERSION_*),
; a struct offset (RL_*_OFF and REQUEST_LINE_SIZE), or an errno
; alias needed for the parser's return convention. Nothing here
; touches syscalls.

%ifndef HTTP_INC
%define HTTP_INC 1

; HTTP version wire numbers used in the parser output and the
; response emitter. Encoded as 10 * major + minor so the two
; supported versions fit in a single byte and callers can
; branch with `cmp version, HTTP_VERSION_11`. Anything outside
; the pair is a reject-at-parse-time case (RFC 9112 §2.5).
%define HTTP_VERSION_10   10
%define HTTP_VERSION_11   11

; struct http_request_line — 40 bytes, caller-owned.
;
;   +0    method_ptr   (u64)  points into the input buffer
;   +8    method_len   (u64)  length of the method token
;  +16    target_ptr   (u64)  points into the input buffer
;  +24    target_len   (u64)  length of the request-target
;  +32    version      (u32)  HTTP_VERSION_10 or HTTP_VERSION_11
;
; The `_ptr` fields are borrowed views into the input `buf`.
; The caller owns the storage; the parser never allocates.
%define RL_METHOD_PTR_OFF     0
%define RL_METHOD_LEN_OFF     8
%define RL_TARGET_PTR_OFF    16
%define RL_TARGET_LEN_OFF    24
%define RL_VERSION_OFF       32
%define REQUEST_LINE_SIZE    40

; errno codes libhttp's parsers return. Per-platform because
; the numeric values differ (macOS BSD legacy vs Linux). Every
; libhttp return is normalized to a `-errno` shape so callers
; using the rest of libs/ do not have to switch mental models.
%ifdef MACOS
%define HTTP_EAGAIN          35
%define HTTP_EINVAL          22
%else
%define HTTP_EAGAIN          11
%define HTTP_EINVAL          22
%endif

%endif ; HTTP_INC
