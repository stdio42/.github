import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[1]

def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / f'{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

policy = load('ci_policy')
bootstrap = load('bootstrap_ci')

class PolicyTests(unittest.TestCase):
    def scan(self, document):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / '.github/workflows/test.yml'
            path.parent.mkdir(parents=True)
            path.write_text(document)
            return policy.scan(Path(directory))

    def test_literal_and_group_routes(self):
        for selector in ['[self-hosted, linux]', '[self-hosted, macOS, ARM64]', '{group: build, labels: [self-hosted, Windows]}']:
            self.assertEqual(self.scan(f'jobs:\n  build:\n    runs-on: {selector}\n'), [])
        for selector in ['ubuntu-latest', '[ubuntu-latest]', '[self-hosted]', '{group: hosted, labels: ubuntu-latest}', '${{ inputs.runner }}']:
            self.assertTrue(self.scan(f'jobs:\n  build:\n    runs-on: {selector}\n'))

    def test_matrix_include_cannot_smuggle_hosted_runner(self):
        document = '''jobs:
  build:
    runs-on: ${{ matrix.runner }}
    strategy:
      matrix:
        runner: [[self-hosted, linux], [self-hosted, macOS]]
'''
        self.assertEqual(self.scan(document), [])
        self.assertTrue(self.scan(document + '        include:\n          - runner: [ubuntu-latest]\n'))
        self.assertTrue(self.scan(document.replace('runner: [[self-hosted, linux], [self-hosted, macOS]]', 'runner: ${{ fromJSON(inputs.matrix) }}')))

    def test_dynamic_inputs_require_validation_dependency(self):
        gated = '''jobs:
  runner-policy:
    uses: stdio42/.github/.github/workflows/validate-runner.yml@main
    with:
      labels: ${{ inputs.runner-labels }}
  build:
    needs: runner-policy
    runs-on: ${{ fromJSON(needs.runner-policy.outputs.labels) }}
'''
        self.assertEqual(self.scan(gated), [])
        self.assertTrue(self.scan(gated.replace('    needs: runner-policy\n', '')))
        self.assertTrue(self.scan(gated.replace('stdio42/.github', 'someone/untrusted')))
        self.assertTrue(self.scan(gated.replace('@main', '@unreviewed-branch')))
        self.assertTrue(self.scan(gated.replace('stdio42/.github/.github/workflows/validate-runner.yml@main', './.github/workflows/validate-runner.yml')))
        self.assertTrue(self.scan('jobs:\n  build:\n    runs-on: ${{ fromJSON(inputs.labels) }}\n'))

    def test_literal_caller_override_is_checked(self):
        self.assertTrue(self.scan('''jobs:
  review:
    uses: stdio42/.github/.github/workflows/claude-code-review.yml@main
    with:
      runs-on: '["ubuntu-latest"]'
'''))

    def test_artifact_actions_and_malformed_yaml_fail(self):
        for action in ['actions/upload-artifact@v4', 'actions/download-artifact@v4']:
            self.assertTrue(self.scan(f'jobs:\n  build:\n    runs-on: [self-hosted, linux]\n    steps:\n      - uses: {action}\n'))
        self.assertTrue(self.scan('jobs: ['))
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'actions/nested/action.yaml'
            path.parent.mkdir(parents=True)
            path.write_text('runs:\n  using: composite\n  steps:\n    - uses: actions/upload-artifact@v4\n')
            self.assertTrue(policy.scan(Path(directory)))

    def test_runtime_validator_executes_and_rejects_unsafe_labels(self):
        data = yaml.load((ROOT / '.github/workflows/validate-runner.yml').read_text(), Loader=yaml.BaseLoader)
        command = data['jobs']['validate']['steps'][0]['run']
        for value, success in [(['self-hosted', 'macOS', 'ARM64'], True), (['ubuntu-latest'], False), (['self-hosted'], False), ('ubuntu-latest', False), (None, False)]:
            with tempfile.NamedTemporaryFile() as output:
                result = subprocess.run(['bash', '-e', '-c', command], env={**os.environ, 'RUNNER_LABELS': json.dumps(value), 'GITHUB_OUTPUT': output.name}, capture_output=True, text=True)
                self.assertEqual(result.returncode == 0, success, result.stderr)
                if success:
                    self.assertEqual(json.loads(Path(output.name).read_text().removeprefix('labels=')), value)
                else:
                    self.assertEqual(Path(output.name).read_text(), '')

class BootstrapTests(unittest.TestCase):
    def test_preserves_existing_instructions_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'AGENTS.md').write_text('# Existing project rules\n')
            for path, content in bootstrap.plan(root).items():
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)
            self.assertTrue((root / 'AGENTS.md').read_text().startswith('# Existing project rules'))
            self.assertIn('@AGENTS.md', (root / 'CLAUDE.md').read_text())
            self.assertEqual(bootstrap.plan(root), {})
            self.assertEqual(policy.scan(root), [])

    def test_does_not_overwrite_a_conflicting_workflow(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / '.github/workflows/org-ci-policy.yml'
            path.parent.mkdir(parents=True)
            path.write_text('existing workflow')
            with self.assertRaises(ValueError):
                bootstrap.plan(root)
            self.assertFalse((root / 'AGENTS.md').exists())
            self.assertEqual(path.read_text(), 'existing workflow')

if __name__ == '__main__':
    unittest.main()
