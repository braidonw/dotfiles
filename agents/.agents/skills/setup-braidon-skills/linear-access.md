# Linear access

Prefer the standard Linear MCP tools available in the current session. Discover the tools before declaring them unavailable. Use [`schpet/linear-cli`](https://github.com/schpet/linear-cli) when the MCP tools are absent or a connection or authentication failure prevents their use. A permission denial is not a transport failure. Do not bypass it or retry an invalid mutation through another transport.

On this machine, prefix every `linear` command with `DENO_TLS_CA_STORE=system,mozilla`. This adds the system certificate store while preserving TLS verification. Use the installed command's `--help` output instead of guessing flags. Run `DENO_TLS_CA_STORE=system,mozilla linear auth whoami` to verify the authenticated identity and workspace. Pass `--workspace` when the intended workspace is ambiguous. If the sandbox cannot access the keychain or network, use the harness's normal scoped escalation before concluding that credentials are absent. Do not re-authenticate or modify credentials solely because a sandboxed check failed.

If credentials are actually missing, ask the user to run `DENO_TLS_CA_STORE=system,mozilla linear auth login`. The user completes authentication themselves. Never print an authentication token.

Prefer JSON output, explicit issue identifiers, and `--description-file` for markdown descriptions. Use `linear api` only when the regular commands do not support an operation. Inspect the installed GraphQL schema before constructing that request. Inspect GraphQL errors even when the command exits successfully.

Read the target immediately before a scoped write. Change only the authorized fields. Read the result afterward and verify those fields plus relevant metadata that should remain unchanged. If a write result is uncertain, read the target before retrying. If a creation result is uncertain, search for the intended item before retrying. These checks apply when switching transports. Stop and report the uncertainty when the result cannot be resolved.

Existing task authorization and project status rules govern every write.
