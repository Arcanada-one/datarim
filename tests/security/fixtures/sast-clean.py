import subprocess

def safe(user_input: str) -> None:
    subprocess.run(["printf", "%s", user_input], check=True)
