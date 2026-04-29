# Security Policy

## Architecture

Scribeosaur is a local-first application:

- All transcription runs on-device using Apple's Neural Engine
- No cloud services, no embedded API keys, no telemetry
- AI features run locally through MLX with model files stored in Application Support or bundled in the installer
- All external URLs in the codebase are public documentation links

## Reporting a Vulnerability

If you discover a security vulnerability, please report it through [GitHub Security Advisories](../../security/advisories/new) rather than opening a public issue.

### What qualifies as a security issue

- Unintended data exfiltration or network access
- Local privilege escalation through bundled binaries
- Path traversal or command injection via file names or URLs
- Credential or session token exposure

### What does not qualify

- Bugs that require physical access to an already-unlocked Mac
- Issues in upstream dependencies (report those to the upstream project)
- Feature requests for additional hardening
