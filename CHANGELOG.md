### 1.1.1

- Bug fixes

## 1.1.0

- `Server`: `onError` handles uncaught exceptions; `errorBody` shapes every `ApiError` response.
- `Server`: `healthPath`, `versionPath`, `openApiPath` and `docsPath` move the built-in endpoints, or turn them off with `null`.
- `Server.serve`: `securityContext` (HTTPS), `shared`, `backlog`, `idleTimeout`, `poweredByHeader` and `banner`.
- `Server.logRequests()`: request logging through `cmdline`, with the level picked by status.
- Uncaught errors are logged with `cmdline` instead of `stderr`.

# 1.0.0

- Initial Release

### 0.0.1

- Initial version