"""Generate backend WAVs and replay them through the real consumer, not a second decoder.
Usage: python tool/test_merchant_wav.py ../acoustic_beacon_consumer --flutter /path/to/flutter
"""
import argparse,subprocess,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/'backend'))
from app.beacon_audio import render_wav
parser=argparse.ArgumentParser()
parser.add_argument('consumer',type=Path)
parser.add_argument('--flutter',default='flutter')
args=parser.parse_args()
consumer=args.consumer.resolve()
subprocess.run([sys.executable,str(root/'tool/sync_d09_profile.py'),str(consumer),'--check'],check=True)
for beacon in [0xABC123,0x96939B]:
 (consumer/f'test/fixtures/merchant-{beacon:06X}.wav').write_bytes(render_wav(beacon))
subprocess.run([args.flutter,'test','test/merchant_wav_test.dart'],cwd=consumer,check=True)
