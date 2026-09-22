#!/usr/bin/env python3
import json, os, random, shutil, socket, ssl, subprocess, time, urllib.error, urllib.request
from urllib.parse import urlparse
from project_state import state_dir, read_key

class JevError(RuntimeError):
    def __init__(self, code, message, *, status=None, body=None):
        super().__init__(f"{code}: {message}")
        self.code=code; self.status=status; self.body=body

RETRYABLE={429,500,502,503,504,529}

def _payload(state, questions, api):
    return json.dumps({"state":state,"model":api.get("model","jev-latest"),"questions":questions},ensure_ascii=False,separators=(",",":")).encode()

def _curl(url,key,payload,timeout,connect_timeout):
    # Send headers and body through stdin config, never secret-bearing argv.
    # JSON string escaping also quotes curl config values (no CR/LF injection).
    settings = "\n".join([
        "header = " + json.dumps("Authorization: Bearer " + key),
        "header = " + json.dumps("Content-Type: application/json"),
        "data-binary = " + json.dumps(payload.decode("utf-8")),
    ]) + "\n"
    cmd=[shutil.which("curl") or "curl","-sS","--connect-timeout",str(connect_timeout),"--max-time",str(timeout),"-X","POST",url,
         "-H","User-Agent: datarim-jev-control/3.0", "--config", "-",
         "-w","\n__DRJEV_HTTP__:%{http_code}\n"]
    try:
        p=subprocess.run(cmd,input=settings.encode(),stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=timeout+3)
    except subprocess.TimeoutExpired as e: raise JevError("READ_TIMEOUT",f"curl exceeded {timeout}s") from e
    if p.returncode:
        err=p.stderr.decode(errors="replace").strip()
        code={6:"DNS_ERROR",7:"CONNECT_ERROR",28:"TIMEOUT",35:"TLS_ERROR",60:"TLS_ERROR"}.get(p.returncode,"TRANSPORT_ERROR")
        raise JevError(code,err or f"curl exit {p.returncode}")
    raw=p.stdout.decode(errors="replace")
    marker="\n__DRJEV_HTTP__:"
    if marker not in raw: raise JevError("INVALID_RESPONSE","missing HTTP status marker")
    body,status_s=raw.rsplit(marker,1); status=int(status_s.strip())
    if status>=400: raise JevError(_http_code(status),f"TypeSafe HTTP {status}",status=status,body=body[:2000])
    try:return json.loads(body)
    except json.JSONDecodeError as e: raise JevError("INVALID_RESPONSE",f"invalid JSON: {e}",status=status,body=body[:2000]) from e

def _urllib(url,key,payload,timeout):
    req=urllib.request.Request(url,data=payload,headers={"Authorization":f"Bearer {key}","Content-Type":"application/json","User-Agent":"datarim-jev-control/3.0"},method="POST")
    try:
        with urllib.request.urlopen(req,timeout=timeout) as r: return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        body=e.read().decode(errors="replace")[:2000]; raise JevError(_http_code(e.code),f"TypeSafe HTTP {e.code}",status=e.code,body=body) from e
    except urllib.error.URLError as e:
        reason=e.reason
        if isinstance(reason,socket.timeout): code="READ_TIMEOUT"
        elif isinstance(reason,ssl.SSLError): code="TLS_ERROR"
        else: code="CONNECT_ERROR"
        raise JevError(code,str(e)) from e
    except socket.timeout as e: raise JevError("READ_TIMEOUT",str(e)) from e

def _http_code(status):
    return {400:"INVALID_REQUEST",401:"AUTH_ERROR",403:"AUTH_ERROR",404:"NOT_FOUND",408:"READ_TIMEOUT",429:"RATE_LIMIT",529:"OVERLOADED"}.get(status,"SERVER_ERROR" if status>=500 else "HTTP_ERROR")

def _kill_switch_reason():
    """Re-read the operator's off switch. Deliberately not cached.

    load_cfg() honours the switch too, but only at load time -- a long-running
    supervised session holds its config for the whole run, so `dr-jev off`
    would not reach it. This is the single choke point for every outbound
    request, so checking here makes the switch effective immediately, which is
    what the CLI tells the operator it does.
    """
    v = os.environ.get("DATARIM_JEV_DISABLE", "").strip().lower()
    if v not in ("", "0", "false", "no"):
        return f"env DATARIM_JEV_DISABLE={v}"
    try:
        if (state_dir() / 'DISABLED').exists():
            return "project Jev disable flag"
    except OSError:
        pass
    return None


def evaluate(state, questions, cfg, *, budget=None):
    off = _kill_switch_reason()
    if off is not None:
        # Every caller already has a fail-open except-branch for JevError.
        raise JevError("DISABLED", f"Jev integration is switched off ({off})")
    # `budget` lets a caller with a hard external deadline (e.g. a Claude Code
    # hook killed after a fixed timeout) request a smaller timeout/retries
    # envelope than the interactive-CLI defaults in cfg['api'], so retry/backoff
    # never runs longer than the caller can actually wait for a fail-open result.
    try:
        key=read_key()
    except (OSError, ValueError) as exc:
        raise JevError("AUTH_ERROR", "Jev key file missing or unsafe") from exc
    if not key: raise JevError("AUTH_ERROR","TYPESAFE_API_KEY is not set")
    api=cfg.get("api",{}); url=api.get("base_url","https://api.typesafe.ai/v1/systemone")
    budget=budget or {}
    payload=_payload(state,questions,api)
    timeout=float(budget.get("timeout_seconds",api.get("timeout_seconds",15)))
    connect=float(budget.get("connect_timeout_seconds",api.get("connect_timeout_seconds",5)))
    retries=int(budget.get("retries",api.get("retries",2)))
    transport=api.get("transport","auto")
    use_curl=(transport=="curl" or (transport=="auto" and shutil.which("curl")))
    last=None
    for i in range(retries+1):
        try:
            out=_curl(url,key,payload,timeout,connect) if use_curl else _urllib(url,key,payload,timeout)
            if not isinstance(out,dict) or not isinstance(out.get("answers"),dict): raise JevError("INVALID_RESPONSE","response has no answers object")
            return out
        except JevError as e:
            last=e
            retry=(e.status in RETRYABLE) or e.code in {"CONNECT_ERROR","READ_TIMEOUT","TIMEOUT","OVERLOADED","RATE_LIMIT","SERVER_ERROR"}
            if not retry or i>=retries: break
            time.sleep(min(4.0,0.35*(2**i)+random.random()*0.15))
    raise last or JevError("UNKNOWN","TypeSafe request failed")

def diagnose(cfg):
    api=cfg.get("api",{}); url=api.get("base_url","https://api.typesafe.ai/v1/systemone"); host=urlparse(url).hostname
    result={"url":url,"transport":"curl" if (api.get("transport","auto") in ("auto","curl") and shutil.which("curl")) else "urllib"}
    t=time.perf_counter()
    try: result["dns"]={"ok":True,"addresses":sorted({x[4][0] for x in socket.getaddrinfo(host,443,type=socket.SOCK_STREAM)})}
    except Exception as e: result["dns"]={"ok":False,"error":str(e)}; return result
    result["dns"]["ms"]=round((time.perf_counter()-t)*1000,1)
    t=time.perf_counter()
    try:
        r=evaluate("Datarim Jev API health check",{"health":{"type":"noul","instructions":"Is this a health-check request?"}},cfg)
        result["api"]={"ok":True,"model":r.get("model"),"usage":r.get("usage",{}),"ms":round((time.perf_counter()-t)*1000,1)}
    except JevError as e: result["api"]={"ok":False,"code":e.code,"error":str(e),"status":e.status,"body":e.body}
    return result
