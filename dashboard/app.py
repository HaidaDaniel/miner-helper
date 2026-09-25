#!/usr/bin/env python3
"""Local web dashboard for WildRig and NVIDIA GPU status."""

import csv
import io
import os
import socket
import subprocess
from pathlib import Path

from flask import Flask, jsonify, render_template_string, request


ROOT = Path(__file__).resolve().parents[1]
MINERCTL = ROOT / "minerctl"
LOG_FILE = ROOT / "miner.log"
app = Flask(__name__)


def _number(value, integer=False):
    value = value.strip()
    if not value or value.upper() in {"N/A", "[N/A]", "NOT SUPPORTED"}:
        return None
    try:
        return int(float(value)) if integer else round(float(value), 1)
    except ValueError:
        return None


def get_gpus():
    query = (
        "index,name,temperature.gpu,fan.speed,utilization.gpu,"
        "power.draw,power.limit,clocks.current.graphics,"
        "clocks.current.memory,pci.bus_id"
    )
    try:
        result = subprocess.run(
            ["nvidia-smi", f"--query-gpu={query}", "--format=csv,noheader,nounits"],
            check=True,
            capture_output=True,
            text=True,
            timeout=4,
        )
    except (FileNotFoundError, subprocess.SubprocessError):
        return [], "nvidia-smi недоступен: проверьте драйвер NVIDIA"

    gpus = []
    for row in csv.reader(io.StringIO(result.stdout)):
        if len(row) < 10:
            continue
        gpus.append(
            {
                "id": row[0].strip(),
                "name": row[1].strip().replace("NVIDIA GeForce ", ""),
                "temp": _number(row[2], integer=True),
                "fan": _number(row[3], integer=True),
                "util": _number(row[4], integer=True),
                "power": _number(row[5]),
                "plimit": _number(row[6], integer=True),
                "core": _number(row[7], integer=True),
                "mem": _number(row[8], integer=True),
                "bus": row[9].strip(),
            }
        )
    return gpus, None


def miner_running():
    try:
        result = subprocess.run(
            [str(MINERCTL), "status"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=10,
            check=False,
        )
        return result.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def get_miner_logs():
    try:
        lines = LOG_FILE.read_text(encoding="utf-8", errors="replace").splitlines()
        return "\n".join(lines[-50:]) or "Лог пока пуст."
    except FileNotFoundError:
        return "Файл лога ещё не создан. Запустите майнер."
    except OSError as exc:
        return f"Ошибка чтения лога: {exc}"


def get_rig_name():
    try:
        value = (ROOT / "rig-name").read_text(encoding="utf-8").strip()
        if value:
            return value
    except OSError:
        pass
    return socket.gethostname()


def get_profile():
    try:
        value = (ROOT / "current-profile").read_text(encoding="utf-8").strip()
        if value and all(char.isalnum() or char in "._-" for char in value):
            return value
    except OSError:
        pass
    return "не выбран"


HTML_TEMPLATE = r'''<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="color-scheme" content="dark"><title>WildRig · {{ rig_name }}</title>
  <style>
    :root{color-scheme:dark;--bg:#0b1018;--panel:#121b27;--line:#253448;--muted:#92a2b5;--text:#edf4fc;--green:#48d597;--amber:#ffc45c;--blue:#71b7ff;--red:#ff7777}
    *{box-sizing:border-box}body{margin:0;background:radial-gradient(ellipse at 15% -20%,#1c3550 0,transparent 42%),var(--bg);color:var(--text);font:15px/1.45 system-ui,-apple-system,"Segoe UI",sans-serif}
    button{font:inherit}.shell{max-width:1500px;margin:auto;padding:26px clamp(16px,3vw,38px) 36px}header{display:flex;align-items:center;justify-content:space-between;gap:18px;flex-wrap:wrap;margin-bottom:24px}
    .identity{display:flex;align-items:center;gap:14px}.mark{display:grid;place-items:center;width:46px;height:46px;border:1px solid #46627e;border-radius:14px;background:#172a3e;color:var(--blue);font-size:23px}
    h1{margin:0;font-size:clamp(20px,3vw,27px);letter-spacing:-.4px}.sub{margin-top:3px;color:var(--muted);font-size:13px}.actions{display:flex;gap:9px;flex-wrap:wrap}
    .btn{border:1px solid var(--line);border-radius:9px;padding:9px 14px;color:var(--text);background:#1a2737;cursor:pointer;transition:.15s}.btn:hover:not(:disabled){transform:translateY(-1px);filter:brightness(1.15)}.btn:disabled{opacity:.5;cursor:wait}
    .start{border-color:#287859;background:#123b30;color:#8ff0c1}.stop{border-color:#744043;background:#3b2228;color:#ffaaaa}.restart{border-color:#786337;background:#382f1d;color:#ffda8e}
    .summary{display:flex;flex-wrap:wrap;gap:9px;margin-bottom:19px}.pill{border:1px solid var(--line);background:#101925d9;color:var(--muted);padding:7px 11px;border-radius:99px;font-size:13px}.pill strong{color:var(--text);font-weight:600}
    .state{display:inline-flex;align-items:center;gap:7px}.dot{width:8px;height:8px;border-radius:50%;background:#7d8da1}.dot.up{background:var(--green);box-shadow:0 0 0 3px #48d59722}.dot.down{background:var(--red);box-shadow:0 0 0 3px #ff777722}
    .section-head{display:flex;justify-content:space-between;align-items:end;gap:12px;margin:22px 0 12px}h2{font-size:16px;margin:0}.hint{color:var(--muted);font-size:12px}
    .gpu-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,440px),1fr));gap:13px}.card{border:1px solid var(--line);border-radius:13px;background:linear-gradient(145deg,#14202e,#101823);overflow:hidden;box-shadow:0 8px 25px #0002}
    .gpu-title{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:13px 16px;border-bottom:1px solid var(--line);background:#ffffff04}.gpu-label{display:flex;align-items:center;gap:10px;font-weight:650}
    .gpu-id{display:inline-grid;place-items:center;min-width:32px;height:25px;padding:0 7px;border-radius:7px;background:#183554;color:var(--blue);font-size:12px}.bus{color:var(--muted);font:11px ui-monospace,monospace}
    .metrics{padding:13px;display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px}.metric{min-width:0;border:1px solid #243346;border-radius:9px;background:#0c141e;padding:10px 9px}
    .metric-name{color:var(--muted);font-size:11px;white-space:nowrap}.metric-value{margin-top:5px;font-size:19px;font-weight:700;white-space:nowrap}.metric-value small{font-size:11px;color:var(--muted);font-weight:500}
    .good{color:var(--green)}.warm{color:var(--amber)}.blue{color:var(--blue)}.clock-row{grid-column:span 2;display:flex;justify-content:space-between;align-items:center}.clock-row .metric-value{margin:0;font-size:15px;color:var(--amber)}
    .empty{border:1px dashed #34465b;border-radius:12px;padding:24px;color:var(--muted);text-align:center;background:#10192588}.log{height:320px;overflow:auto;padding:15px;color:#a7edc5;background:#080e15;font:12px/1.55 ui-monospace,SFMono-Regular,Consolas,monospace;white-space:pre-wrap;overflow-wrap:anywhere}
    .footer{display:flex;justify-content:space-between;gap:10px;padding:9px 13px;border-top:1px solid var(--line);color:var(--muted);font-size:12px}#notice{min-height:20px;margin:8px 0 0;color:var(--amber);font-size:13px}
    @media(max-width:520px){.shell{padding:18px 12px 26px}.actions{width:100%}.btn{flex:1;padding:9px 8px;font-size:13px}.metrics{grid-template-columns:repeat(2,minmax(0,1fr))}.clock-row{grid-column:span 1}.bus{font-size:10px}.gpu-title{padding:12px}}
  </style>
</head>
<body><main class="shell">
  <header><div class="identity"><div class="mark" aria-hidden="true">◈</div><div><h1>{{ rig_name }}</h1><div class="sub">WildRig Multi · панель управления ригом</div></div></div>
    <div class="actions"><button class="btn start" data-action="start">▶ Запустить</button><button class="btn stop" data-action="stop">■ Остановить</button><button class="btn restart" data-action="restart">↻ Перезапустить</button></div>
  </header>
  <div class="summary"><div class="pill state"><span id="state-dot" class="dot"></span><strong id="miner-state">Проверка…</strong></div><div class="pill">Профиль: <strong>{{ profile }}</strong></div><div class="pill">Обновление: <strong>2 сек</strong></div></div>
  <div class="section-head"><h2>Видеокарты</h2><span id="gpu-count" class="hint">Опрос NVIDIA</span></div>
  <section id="gpu-grid" class="gpu-grid"><div class="empty">Получение данных GPU…</div></section>
  <div class="section-head"><h2>Журнал WildRig</h2><span class="hint">Последние 50 строк</span></div>
  <section class="card"><div id="log" class="log">Загрузка журнала…</div><div class="footer"><span>Обновляется автоматически</span><span id="updated"></span></div></section><div id="notice" role="status" aria-live="polite"></div>
</main>
<script>
  const esc=value=>String(value??'—').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const metric=(title,value,unit,tone='')=>'<div class="metric"><div class="metric-name">'+title+'</div><div class="metric-value '+tone+'">'+esc(value)+' <small>'+unit+'</small></div></div>';
  function gpuCard(g){const tempTone=Number(g.temp)>=75?'warm':'good';return '<article class="card"><div class="gpu-title"><div class="gpu-label"><span class="gpu-id">GPU '+esc(g.id)+'</span><span>'+esc(g.name)+'</span></div><span class="bus">'+esc(g.bus)+'</span></div><div class="metrics">'+metric('ТЕМПЕРАТУРА',g.temp,'°C',tempTone)+metric('ВЕНТИЛЯТОР',g.fan,'%','blue')+metric('ЗАГРУЗКА',g.util,'%','good')+metric('МОЩНОСТЬ',g.power,'W')+'<div class="metric clock-row"><span class="metric-name">ЧАСТОТА ЯДРА</span><span class="metric-value">'+esc(g.core)+' <small>MHz</small></span></div><div class="metric clock-row"><span class="metric-name">ЧАСТОТА ПАМЯТИ</span><span class="metric-value">'+esc(g.mem)+' <small>MHz</small></span></div></div></article>';}
  async function updateDashboard(){try{const response=await fetch('/api/status',{cache:'no-store'});if(!response.ok)throw new Error('HTTP '+response.status);const data=await response.json();document.getElementById('miner-state').textContent=data.running?'Майнинг активен':'Майнер остановлен';document.getElementById('state-dot').className='dot '+(data.running?'up':'down');document.getElementById('gpu-count').textContent=data.gpu_error||data.gpus.length+' GPU';document.getElementById('gpu-grid').innerHTML=data.gpus.length?data.gpus.map(gpuCard).join(''):'<div class="empty">'+esc(data.gpu_error||'NVIDIA GPU не обнаружена')+'</div>';document.getElementById('log').textContent=data.logs;document.getElementById('log').scrollTop=document.getElementById('log').scrollHeight;document.getElementById('updated').textContent='Обновлено '+new Date().toLocaleTimeString();}catch(error){document.getElementById('notice').textContent='Панель не получила данные: '+error.message;}}
  async function controlMiner(action){if(action==='stop'&&!confirm('Остановить майнер на этом риге?'))return;document.querySelectorAll('[data-action]').forEach(button=>button.disabled=true);const notice=document.getElementById('notice');notice.textContent='Выполняется команда…';try{const response=await fetch('/api/control',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action})});const data=await response.json();if(!response.ok)throw new Error(data.message||'HTTP '+response.status);notice.textContent='Команда выполнена.';setTimeout(updateDashboard,700);}catch(error){notice.textContent='Не удалось выполнить команду: '+error.message;}finally{document.querySelectorAll('[data-action]').forEach(button=>button.disabled=false);}}
  document.querySelectorAll('[data-action]').forEach(button=>button.addEventListener('click',()=>controlMiner(button.dataset.action)));updateDashboard();setInterval(updateDashboard,2000);
</script></body></html>'''


@app.get("/")
def index():
    return render_template_string(HTML_TEMPLATE, rig_name=get_rig_name(), profile=get_profile())


@app.get("/api/status")
def status():
    gpus, gpu_error = get_gpus()
    return jsonify(running=miner_running(), gpus=gpus, gpu_error=gpu_error, logs=get_miner_logs())


@app.post("/api/control")
def control():
    payload = request.get_json(silent=True) or {}
    action = payload.get("action")
    if action not in {"start", "stop", "restart"}:
        return jsonify(status="error", message="Неизвестная команда"), 400
    try:
        result = subprocess.run(
            [str(MINERCTL), action], capture_output=True, text=True, timeout=30, check=False
        )
    except subprocess.TimeoutExpired:
        return jsonify(status="error", message="Истекло время ожидания команды"), 504
    except OSError:
        app.logger.exception("Cannot run minerctl")
        return jsonify(status="error", message="Не удалось выполнить minerctl"), 500
    if result.returncode:
        message = (result.stderr or result.stdout or "Команда завершилась с ошибкой").strip()
        return jsonify(status="error", message=message[-500:]), 500
    return jsonify(status="ok")


if __name__ == "__main__":
    app.run(
        host=os.environ.get("DASHBOARD_HOST", "127.0.0.1"),
        port=int(os.environ.get("DASHBOARD_PORT", "8080")),
        debug=False,
    )
