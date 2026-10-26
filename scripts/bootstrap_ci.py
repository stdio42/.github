#!/usr/bin/env python3
"""Install repository-local org instructions and a thin policy workflow."""
import argparse
from pathlib import Path

SOURCE = Path(__file__).resolve().parent.parent


def plan(root):
    snippet = (SOURCE / 'templates/AGENTS.md').read_text()
    agent = root / 'AGENTS.md'
    current = agent.read_text() if agent.exists() else ''
    writes = {}
    if '<!-- stdio42-org-policy:start -->' not in current:
        writes[agent] = (current.rstrip() + '\n\n' if current else '') + snippet
    claude = root / 'CLAUDE.md'
    current_claude = claude.read_text() if claude.exists() else ''
    if '@AGENTS.md' not in current_claude:
        writes[claude] = (current_claude.rstrip() + '\n\n' if current_claude else '') + '# Organization instructions\n\n@AGENTS.md\n'
    policy = root / '.github/workflows/org-ci-policy.yml'
    desired = (SOURCE / 'workflow-templates/org-ci-policy.yml').read_text()
    if policy.exists() and policy.read_text() != desired:
        raise ValueError(f'{policy} exists with different content; reconcile it manually (no files changed)')
    if not policy.exists():
        writes[policy] = desired
    return writes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('--apply', action='store_true', help='Write changes; default is a preview')
    args = parser.parse_args()
    root = args.root.resolve()
    if not (root / '.git').exists():
        parser.error('target must be a Git checkout')
    try:
        writes = plan(root)
    except ValueError as error:
        parser.error(str(error))
    for path, content in writes.items():
        print(('write ' if args.apply else 'would write ') + str(path.relative_to(root)))
        if args.apply:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
    if not writes:
        print('Organization pointers and policy caller already installed.')
    elif not args.apply:
        print('Preview only. Pass --apply to write.')


if __name__ == '__main__':
    main()
