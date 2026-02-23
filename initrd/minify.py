import subprocess

def minify(code: str) -> str:
    return subprocess.run(["luamin", "-c", code], capture_output=True, check=True).stdout.decode().strip()
