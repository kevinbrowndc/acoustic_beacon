"""Synchronize the production D09 radio profile into the existing consumer checkout."""
import json
from pathlib import Path
import argparse
root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('consumer',type=Path)
parser.add_argument('--check',action='store_true')
args=parser.parse_args()
profile=json.loads((root/'backend/app/d09_profile.json').read_text())
source='// Generated from backend/app/d09_profile.json; run tool/sync_d09_profile.py.\nabstract final class D09Profile {\n'
for key,name in [('sample_rate','sampleRate'),('zero_hz','zeroHz'),('one_hz','oneHz'),('symbol_ms','symbolMs')]:
 kind="double" if key.endswith("_hz") else "int"
 source+=f"  static const {kind} {name} = {profile[key]};\n"
source+='}\n'
target=args.consumer/'lib/protocol/d09_profile.dart'
if args.check:
 assert target.read_text()==source,'D09 profile drift; rerun synchronization'
else:target.write_text(source)
