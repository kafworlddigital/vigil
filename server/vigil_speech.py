"""Bounded Piper worker. Text arrives only on stdin, never arguments or logs."""
from pathlib import Path
import sys,wave,json
from piper import PiperVoice
from piper.config import PiperConfig
import onnxruntime

model=Path('/srv/projects/vigil-private/piper/en_GB-alan-medium.onnx')
options=onnxruntime.SessionOptions()
options.intra_op_num_threads=1;options.inter_op_num_threads=1
voice=PiperVoice(config=PiperConfig.from_dict(json.loads(Path(str(model)+'.json').read_text())),
    session=onnxruntime.InferenceSession(str(model),sess_options=options,providers=['CPUExecutionProvider']))
with wave.open(sys.argv[1],'wb') as output:
    voice.synthesize_wav(sys.stdin.read(1200)[:300],output)
