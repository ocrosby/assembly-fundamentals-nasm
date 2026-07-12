# libs/http/

HTTP/1.1 wire-format primitives packaged as the static
archive `libhttp.a`. Tracks the current IETF standards —
[RFC 9110](https://www.rfc-editor.org/rfc/rfc9110) (HTTP
semantics) and [RFC 9112](https://www.rfc-editor.org/rfc/rfc9112)
(HTTP/1.1 message syntax) — not the obsoleted
[RFC 2616](https://datatracker.ietf.org/doc/html/rfc2616).

See [`../README.md`](../README.md) for the shared ABI, error
convention, and no-libc policy every archive under `libs/`
follows.

## Version

**v1.0** — first cut: request-line parser only.
`http_parse_request_line` parses the `method SP target SP
HTTP/1.x CRLF` start line into a caller-supplied 40-byte
`struct http_request_line` view. The struct fields borrow
into the input buffer — no allocation, no copies.

## Exported symbols

| Symbol                       | Args                          | Return                    | Notes                                                                 |
| ---------------------------- | ----------------------------- | ------------------------- | --------------------------------------------------------------------- |
| `http_parse_request_line`    | `buf`, `len`, `out`           | bytes consumed or -errno  | See RFC 9112 §3. `-HTTP_EAGAIN` when the CRLF is not yet in `buf`; `-HTTP_EINVAL` for a malformed line. |

## The `struct http_request_line` layout

40 bytes, defined in `http.inc`:

```
+0    method_ptr   (u64)  points into the input buffer
+8    method_len   (u64)  length of the method token
+16   target_ptr   (u64)  points into the input buffer
+24   target_len   (u64)  length of the request-target
+32   version      (u32)  HTTP_VERSION_10 (10) or HTTP_VERSION_11 (11)
```

`*_ptr` fields are borrowed views into the buffer the caller
passed in. If the buffer is a `libbuf` mapping that later
grows, the pointers stored here are invalidated with it. The
common pattern is: parse into locals, act on the tokens
immediately, then release the view before appending more
bytes.

## Errno codes

Both parsers return a `-errno` shape identical to the rest
of `libs/`. Two codes come back today:

- **`-HTTP_EAGAIN`** — not enough bytes to decide yet.
  Caller reads more input and retries with the same offset.
  Matches the shape a non-blocking read loop wants: the
  parser is a strict function of what it has seen so far.
- **`-HTTP_EINVAL`** — bytes seen so far cannot be a valid
  request line. Caller closes the connection or replies
  `400 Bad Request`.

The per-platform numeric values differ (macOS 35 / Linux 11
for EAGAIN; both 22 for EINVAL). Callers who want to
distinguish partial-input from truly-malformed compare
against `HTTP_EAGAIN` / `HTTP_EINVAL` symbolic names from
`http.inc`.

## Dependency graph

```
libhttp → libstr (memchr, memcmp)
```

Every future addition — header block parser, chunked
decoder, response emitter, URL parser — extends this graph
downward: `libbuf` for growing buffers, `libtime` for the
`Date:` header, `libsock` + `libresolv` for the eventual
client and server helpers.

## Building

```
make          # produces libhttp.a
make build    # object files only
make test     # rebuild + run the smoke
make clean
```

## Explicit non-goals

Documented in the plan file
`~/.claude/plans/read-the-http-specification-peaceful-map.md`
and in `TODO.md` at the repo root:

- **TLS / HTTPS** — would need OpenSSL, which conflicts
  with the direct-syscall rule.
- **HTTP/2, HTTP/3** — different wire format entirely.
- **Compression** (`gzip`, `br`) — advertise `identity`
  only.
- **Cookies, CORS, WebSocket upgrade** — application-layer
  concerns; not part of the wire spec.

## Not here yet

- **Header block parser** — `http_parse_headers(buf, len,
  out_arr, cap)` filling an array of `{name_ptr, name_len,
  value_ptr, value_len}` views. Uses libstr's `strncasecmp`
  from v1.3 for RFC 9110 §5.1 case-insensitive matching.
- **Chunked transfer decoder** — RFC 9112 §7.
- **Content-Length body reader** — the simpler of the two
  body-framing paths.
- **Response emitter** — writes the status line, headers
  (including a Date: from libtime's `format_time_rfc1123`),
  and body into a `libbuf`.
- **URL parser** — RFC 9112 §3.2 request-target forms.
- **`http_serve` and `http_client_get` composed helpers**
  — the server loop and one-shot client that tie
  everything together.
