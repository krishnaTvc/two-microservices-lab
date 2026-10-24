#!/usr/bin/env python3
"""Fill policy templates locally. This script makes no AWS API calls."""
import argparse
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--account-id', required=True)
parser.add_argument('--region', required=True)
parser.add_argument('--bucket', required=True)
parser.add_argument('--app-instance-id', required=True)
parser.add_argument('--owner', required=True)
parser.add_argument('--repo', required=True)
args = parser.parse_args()
checks = {
    'account_id': r'[0-9]{12}',
    'region': r'[a-z]{2}(?:-[a-z]+)+-[0-9]+',
    'bucket': r'[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]',
    'app_instance_id': r'i-[a-f0-9]+',
    'owner': r'[A-Za-z0-9-]+',
    'repo': r'[A-Za-z0-9_.-]+',
}
for field, pattern in checks.items():
    if not re.fullmatch(pattern, getattr(args, field)):
        parser.error(f'Invalid {field.replace("_", "-")}')
project = Path(__file__).resolve().parents[1]
output = project / 'iam' / 'rendered'
output.mkdir(exist_ok=True)
for template in (project / 'iam').glob('*.template.json'):
    text = template.read_text()
    for key, value in vars(args).items():
        text = text.replace('<' + key.upper() + '>', value)
    json.loads(text)
    path = output / template.name.replace('.template', '')
    path.write_text(text)
    print(path.relative_to(project))
