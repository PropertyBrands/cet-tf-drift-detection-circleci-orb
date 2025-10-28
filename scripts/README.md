# Build Scripts

This directory contains scripts for building and maintaining the orb.

## generate_python_wrapper.sh

Generates `src/scripts/write_validate_drift.sh` from `src/scripts/validate_drift.py`.

### Why is this needed?

CircleCI's orb packer requires that `<<include()>>` directives be standalone in YAML files - they cannot be mixed with other bash code in multiline strings. To work around this limitation while maintaining a single source of truth for the Python validation script, we:

1. Keep the canonical Python source in `src/scripts/validate_drift.py`
2. Use this build script to generate a shell wrapper that embeds the Python code in a heredoc
3. The YAML command uses `<<include(scripts/write_validate_drift.sh)>>` which the orb packer can process

### Usage

Run this script **before** packing the orb whenever you've modified `validate_drift.py`:

```bash
./scripts/generate_python_wrapper.sh
circleci orb pack src > orb.yml
```

### Development Workflow

1. Edit `src/scripts/validate_drift.py` with your changes
2. Run `./scripts/generate_python_wrapper.sh` to regenerate the wrapper
3. Pack the orb: `circleci orb pack src > orb.yml`
4. Commit both files: `validate_drift.py` and the generated `write_validate_drift.sh`

**Note:** Do NOT edit `write_validate_drift.sh` manually - your changes will be overwritten!

