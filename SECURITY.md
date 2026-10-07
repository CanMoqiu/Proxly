# Security policy

## Reporting a vulnerability

Please do not open a public issue for a suspected security vulnerability. Use the repository's [private vulnerability reporting form](https://github.com/CanMoqiu/Proxly/security/advisories/new). If GitHub does not make the form available for your account, contact [@CanMoqiu](https://github.com/CanMoqiu) through GitHub and do not include sensitive data in the initial message.

Include the affected version or commit, the smallest reproducible description, impact, and a safe way to reproduce the issue. Do not include Clash tokens, SSH passwords, private keys, router addresses, personal data, or signed application credentials.

## Scope

Reports about credential handling, SSH host verification, YAML path restrictions, archive extraction, update integrity, authentication state, or release signing are especially useful. This project does not operate proxy nodes or network services; reports about a user's third-party controller should include only sanitized evidence.

## Supported versions

The latest release and the current `main` branch receive security fixes. Older releases are retained for historical reference and do not receive backported fixes unless explicitly stated.
