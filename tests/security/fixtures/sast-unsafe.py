import subprocess

def unsafe(user_input: str) -> None:
    subprocess.run(user_input, shell=True, check=True)
    eval(user_input)
