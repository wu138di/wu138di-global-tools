from pathlib import Path
import subprocess,shutil
ROOT=Path(__file__).resolve().parents[1]
for variant,folder in [('u30',ROOT),('f50',ROOT/'variants/f50')]:
 subprocess.run(['python','scripts/build.py'],cwd=folder,check=True)
 for ext in ['js','txt']:
  shutil.copy2(folder/('dist/wu138di-全球上网-V1.0.'+ext),ROOT/('dist/wu138di-global-tools-'+variant+'-v1.0.1.'+ext))
 shutil.copy2(folder/'dist/manifest.json',ROOT/('dist/manifest-'+variant+'.json'))
