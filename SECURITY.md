# Security Policy

## Supported versions

Only the latest `main` branch is supported.

## Reporting a vulnerability

**Do not open a public issue for security reports.** Use GitHub's private
security advisory ("Report a vulnerability" on the Security tab) or contact
the maintainers directly (see the repository owner's profile).

Include: affected component, reproduction steps, and impact assessment. You
will get an acknowledgment within 72 hours.

## Security-relevant defaults

- Passwords: PBKDF2-HMAC-SHA256 (100k iterations) via `zmodu.security.PasswordEncoder`
- Tokens: HMAC-SHA256 JWTs, persisted in `auth_tokens` with expiry; login rate-limit (5 / 15 min / user)
- `[jwt] require_strong_secret: true` refuses startup when the shipped default secret is present
- All SQL is parameterized (audited in Phase 39); WS handshakes are token-authenticated and rate-limited (30/s/IP)
- Response headers: CSP (`default-src 'none'`), HSTS, frame/type protections via `securityHeaders`

## Scope notes

- The `config.yaml` shipped in the repository is a placeholder set — never deploy it unchanged.
- `_ref/` (OpenIM reference implementations) is local-only and not part of the repository.
