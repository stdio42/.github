#!/usr/bin/env python3
"""Check Actions routing/artifact policy without executing project code."""
import argparse
import json
from pathlib import Path
import re
import sys
import yaml

VALIDATOR = 'stdio42/.github/.github/workflows/validate-runner.yml@'
EXPRESSION = re.compile(r'^\$\{\{\s*(.*?)\s*\}\}$')


def validate_labels(labels):
    if not isinstance(labels, list) or not labels or not all(isinstance(x, str) and x.strip() for x in labels):
        raise ValueError('runner labels must be a nonempty JSON array of strings')
    literal = {x.lower() for x in labels if '${{' not in x}
    if 'self-hosted' not in literal:
        raise ValueError('runner labels must include literal self-hosted')
    if not literal.intersection({'linux', 'macos', 'windows'}):
        raise ValueError('runner labels must include a literal OS: linux, macOS or Windows')
    return labels


def validate_selector(selector, job, jobs, workflow_path):
    if isinstance(selector, dict):
        selector = selector.get('labels')
    if isinstance(selector, list):
        validate_labels(selector)
        return
    match = EXPRESSION.fullmatch(selector) if isinstance(selector, str) else None
    if match:
        expr = match.group(1)
        matrix = re.fullmatch(r'matrix\.([\w-]+)', expr)
        if matrix:
            strategy = job.get('strategy', {}).get('matrix', {})
            if not isinstance(strategy, dict):
                raise ValueError('dynamic matrix routing cannot be proven safe')
            axis = matrix.group(1)
            options = strategy.get(axis, [])
            if not isinstance(options, list):
                raise ValueError('matrix runner choices must be a finite literal list')
            options = options + [row[axis] for row in strategy.get('include', []) if isinstance(row, dict) and axis in row]
            if not options:
                raise ValueError('matrix selector has no runner choices')
            for option in options:
                validate_labels(option)
            return
        gated = re.fullmatch(r'fromJSON\(needs\.([\w-]+)\.outputs\.labels\)', expr)
        if gated:
            gate_id = gated.group(1)
            needs = job.get('needs', [])
            needs = [needs] if isinstance(needs, str) else needs
            gate = jobs.get(gate_id, {})
            use = gate.get('uses', '')
            remote = isinstance(use, str) and re.fullmatch(re.escape(VALIDATOR) + r'(main|[0-9a-f]{40})', use)
            local = workflow_path.parent / 'validate-runner.yml'
            trusted = Path(__file__).resolve().parents[1] / '.github/workflows/validate-runner.yml'
            local_matches = use == './.github/workflows/validate-runner.yml' and local.exists() and local.read_bytes() == trusted.read_bytes()
            if gate_id in needs and (remote or local_matches):
                return
    raise ValueError('runner routing is not provably self-hosted; use literal labels or validate-runner outputs')


def scan_yaml(path):
    errors = []
    try:
        # BaseLoader keeps GitHub's `on` key as a string (YAML 1.1 otherwise makes it True).
        data = yaml.load(path.read_text(), Loader=yaml.BaseLoader)
        if not isinstance(data, dict):
            raise ValueError('expected YAML mapping')
        jobs = data.get('jobs', {})
        if not isinstance(jobs, dict):
            raise ValueError('jobs must be a mapping')
        for name, job in jobs.items():
            if not isinstance(job, dict):
                raise ValueError(f'job {name} must be a mapping')
            if 'runs-on' in job:
                try:
                    validate_selector(job['runs-on'], job, jobs, path)
                except ValueError as error:
                    errors.append(f'{path}: jobs.{name}: {error}')
            elif 'uses' not in job:
                errors.append(f'{path}: jobs.{name}: missing runs-on or reusable workflow')
        # Inspect all `uses` nodes, including composite actions and reusable callers.
        def walk(node):
            if isinstance(node, dict):
                use = node.get('uses', '')
                if isinstance(use, str) and re.match(r'^actions/(upload|download)-artifact(?:/|@|$)', use, re.I):
                    errors.append(f'{path}: GitHub artifact action forbidden; use organization S3 actions')
                # Check literal runner overrides in callers. Dynamic overrides are
                # checked by the called workflow's validate-runner prerequisite.
                if isinstance(node.get('with'), dict):
                    for key, value in node['with'].items():
                        if key in ('runner-labels', 'submit-runner-labels', 'runs-on') and isinstance(value, str) and '${{' not in value:
                            try:
                                validate_labels(json.loads(value))
                            except (ValueError, TypeError) as error:
                                errors.append(f'{path}: with.{key}: {error}')
                for value in node.values():
                    walk(value)
            elif isinstance(node, list):
                for value in node:
                    walk(value)
        walk(data)
    except (OSError, ValueError, yaml.YAMLError, TypeError, AttributeError) as error:
        errors.append(f'{path}: invalid workflow/action: {error}')
    return errors


def scan(root):
    paths = set()
    for base in [root / '.github/workflows', root / '.github/actions', root / 'actions']:
        if base.exists():
            paths.update(p for p in base.rglob('*') if p.suffix in ('.yml', '.yaml'))
    return [error for path in sorted(paths) for error in scan_yaml(path)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', nargs='?', type=Path, default=Path('.'))
    args = parser.parse_args()
    errors = scan(args.root)
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        return 1
    print('CI policy passed: self-hosted routing and organization artifact storage.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
