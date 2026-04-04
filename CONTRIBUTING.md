# Contributing to apache-cf-realip

Thanks for your interest in improving apache-cf-realip! This Apache module automatically fetches Cloudflare IP ranges and generates RemoteIPTrustedProxy configuration.

## Ways to Help

- **Report bugs**: Include reproduction steps, environment details (Apache version, OS, module config)
- **Propose enhancements**: Outline use case and provide minimal configuration examples
- **Improve documentation**: Fix clarity, add examples, correct spelling/grammar
- **Add tests**: Edge cases, configuration validation, network error handling
- **Performance testing**: Benchmark impact on request processing

## Development Setup

### Prerequisites

- Rust toolchain (stable, 1.75+)
- Apache httpd development headers (`apache2-dev` / `httpd-devel`)
- C compiler (for the thin FFI shim)
- Git for version control

### Local Development

1. **Clone the repository**:
   ```bash
   git clone https://github.com/RumenDamyanov/apache-cf-realip.git
   cd apache-cf-realip
   ```

2. **Build the module**:
   ```bash
   cargo build --release
   # Then build the C shim and link
   make
   ```

3. **Run tests**:
   ```bash
   cargo test
   bash test/integration_test.sh
   ```

## Coding Guidelines

- Follow Rust idioms and clippy recommendations
- Use `cargo fmt` before committing
- Keep unsafe blocks minimal and well-documented
- Test with `apachectl configtest` before submitting changes
- Keep changes focused and minimal

## Pull Request Process

1. Fork the repository
2. Create a feature branch from `master`
3. Make your changes with clear commit messages
4. Ensure `cargo test` and `cargo clippy` pass
5. Submit a pull request with a description of changes

## Questions?

Open a [discussion](https://github.com/RumenDamyanov/apache-cf-realip/discussions) or [issue](https://github.com/RumenDamyanov/apache-cf-realip/issues).
