# Contributing to Runnermatic

Thank you for your interest in contributing! Runnermatic is a self-hosted runner management tool, so contributions that improve security, reliability, and ease of setup are especially welcome.

## Ways to Contribute

### 1. Report Issues
- Found a bug in a script? [Open an issue](https://github.com/runnermatic/runnermatic/issues)
- Have a better approach for runner registration or management? Describe your setup
- Documentation unclear? Let us know

### 2. Submit Pull Requests
- Fix bugs or improve idempotency in scripts
- Add support for new platforms or runner configurations
- Improve documentation and security guidance
- Add monitoring, alerting, or hardening configurations

### 3. Share Your Experience
- How are you managing self-hosted runners at scale?
- What GitHub App permission patterns work well?
- Share your systemd hardening configurations

## Contribution Guidelines

### Code Style
- **Shell scripts**: Follow [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- **JavaScript**: Use Node.js built-in modules only (no npm dependencies)
- **YAML**: Use consistent 2-space indentation
- **Markdown**: Use clear headings and concise language

### Commit Messages
Follow [Conventional Commits](https://www.conventionalcommits.org/):
```
feat: add ephemeral runner support
fix: correct token expiry handling in JWT generation
docs: clarify GitHub App permission requirements
```

### Pull Request Process

1. Fork the repository
2. Create a feature branch
3. Make focused, atomic changes
4. Test on a Linux x64 host with systemd
5. Submit PR with clear description

## Security

If you discover a security issue, please report it privately rather than opening a public issue. Email mike@kwyk.net.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
