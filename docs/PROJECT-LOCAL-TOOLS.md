# Project-Local Tool Installation Philosophy

## Why Project-Local?

Engineers working on this project also work on many other similar but distinct projects. Each project may require different versions of the same tools. Installing tools globally or in user directories creates version conflicts and "works on my machine" problems.

## Our Approach

**All tools that CAN be installed project-locally, MUST be installed project-locally.**

### What We Install Project-Locally

| Tool | Method | Location | Why |
|------|--------|----------|-----|
| Python packages | `uv` | `.venv/` | Isolated Python environment per project |
| shellcheck | `mise` | `.mise/` | mise manages per-project tool versions |
| shfmt | `mise` | `.mise/` | mise manages per-project tool versions |
| tofu/terraform | `mise` | `.mise/` | mise manages per-project tool versions |
| kubectl | `mise` | `.mise/` | mise manages per-project tool versions |
| helm | `mise` | `.mise/` | mise manages per-project tool versions |
| packer | `mise` | `.mise/` | mise manages per-project tool versions |

### What We DON'T Install

Some tools CANNOT be installed project-locally and must be installed by the user:

| Tool | Why System Install | How to Install |
|------|-------------------|----------------|
| hadolint | No project-local option | `brew install hadolint` |
| Docker | System daemon required | Docker Desktop or `brew install docker` |
| uv | Bootstrap tool | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| mise | Bootstrap tool | `curl https://mise.run \| sh` |
| just | Command runner | `brew install just` |

When a tool cannot be installed project-locally, `just setup` will:
1. **NOT** attempt to install it
2. **FAIL** with a clear error message
3. **TELL** the user exactly how to install it

## Tool Versions

### Controlled by This Project

These are defined in project files:

- **Python tools**: Versions in `.venv/` managed by `uv`
- **mise tools**: Versions in `mise.toml`
  ```toml
  [tools]
  terraform = "1.7"  # Actually installs tofu
  kubectl = "1.29"
  helm = "3.14"
  shellcheck = "latest"
  shfmt = "latest"
  ```

### Controlled by User

These are user's responsibility:
- `hadolint` version (whatever brew/system provides)
- `uv` version (user decides when to upgrade)
- `mise` version (user decides when to upgrade)
- `just` version (user decides when to upgrade)

## Benefits

1. **No Conflicts**: Work on multiple projects with different tool versions
2. **Reproducible**: Everyone on the team uses the same tool versions
3. **Isolated**: Changes to one project don't affect others
4. **Clean**: `rm -rf .venv .mise` and you're back to zero
5. **Explicit**: Tool versions are in version control

## Usage

### Initial Setup

```bash
# First time setup
just setup  # Creates .venv/, installs Python packages

# Install mise-managed tools (from mise.toml)
mise install  # Creates .mise/, installs shellcheck, shfmt, etc.

# Install system tools (user's responsibility)
brew install hadolint
```

### Daily Usage

All commands automatically use project-local tools:

```bash
just lint        # Uses .venv/bin/ruff, .venv/bin/yamllint
just lint-shell  # Uses mise-installed shellcheck
just tf-plan staging  # Uses mise-installed tofu
```

### Checking What's Installed

```bash
# See what mise will install
mise ls

# See what Python packages are installed
uv pip list

# See where tools are coming from
which tofu      # Should show .mise/installs/...
which ruff      # Should show .venv/bin/ruff
which hadolint  # Should show system path
```

## Cleaning Up

```bash
# Clean project-local tools
just clean  # Removes .venv/, .terraform.d/, etc.

# Full reset (including mise tools)
rm -rf .venv .mise .terraform.d
just setup
mise install
```

## Why Not Docker for Everything?

We considered putting all linting in Docker containers, but:
- Slower startup time for quick checks
- Harder to integrate with IDEs
- Breaks local development workflow
- Still need Docker installed (system tool)

Our hybrid approach:
- Project-local for fast, frequent tools (linters, formatters)
- Docker for runtime environments (CI jobs, builds)

## Adding New Tools

### If Tool Can Be Project-Local

1. **Python tool**: Add to `_setup-linters` in justfile
   ```bash
   uv pip install new-python-tool
   ```

2. **Other tool**: Add to `mise.toml`
   ```toml
   [tools]
   new-tool = "1.2.3"
   ```

3. Update lint command to use it:
   ```bash
   # Python tool
   .venv/bin/new-python-tool check

   # mise tool (just use command name, mise adds to PATH)
   new-tool check
   ```

### If Tool MUST Be System-Wide

1. **DON'T** install it in `just setup`
2. **ADD** clear instructions in `_setup-linters` output
3. **FAIL** lint command if tool not found with helpful error

## Examples from Other Projects

This approach is used by:
- **Rust projects**: `cargo` creates per-project `target/` dirs
- **Node projects**: `npm` creates per-project `node_modules/`
- **Python projects**: `venv` creates per-project `.venv/`
- **Ruby projects**: `bundler` creates per-project `.bundle/`

We're applying the same philosophy to infrastructure tooling.

## FAQ

**Q: Why not just use Docker for everything?**
A: Docker adds overhead and breaks IDE integration. Project-local tools are faster and more convenient.

**Q: What if I want a different version of a tool?**
A: Edit `mise.toml` or install your version system-wide. mise uses project version by default, falls back to system.

**Q: Can I use my system tools instead?**
A: Yes! If mise finds a tool in PATH, lint commands will use it as fallback. But project versions are preferred for consistency.

**Q: What about CI?**
A: CI runs `just setup` and `mise install` just like local development. Same tools, same versions.

**Q: How do I upgrade a tool?**
A: Edit `mise.toml`, commit the change. Everyone gets the upgrade on next `mise install`.

## Summary

✅ **DO**: Install tools project-locally via uv/mise
✅ **DO**: Let user install system tools (hadolint, Docker, etc.)
✅ **DO**: Fail with helpful error if system tool missing
❌ **DON'T**: Install tools in ~/.local/bin or system-wide
❌ **DON'T**: Assume tools are in PATH
❌ **DON'T**: Silently skip when tools are missing (except warnings for optional tools)

**The goal**: Every engineer can work on this project and 10 other similar projects without any tool version conflicts.
