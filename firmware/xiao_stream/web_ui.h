#pragma once

// Lightweight, zero-dependency standalone Web UI served directly by the ESP32-S3
// Works on any phone, tablet, or computer (including portable power-bank AP mode).
static const char kWebUiHtml[] = R"HTML(<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>XIAO S3 Ultra Stream</title>
<style>
  :root{--bg:#0b0d12;--card:#141822;--border:#232a3a;--text:#eef2f7;--muted:#8b95a7;--acc:#3b82f6;--ok:#10b981;--warn:#f59e0b}
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--text);font:14px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;padding:16px}
  .wrap{max-width:1100px;margin:0 auto;display:grid;gap:14px}
  header{display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:10px}
  h1{margin:0;font-size:18px;font-weight:600;letter-spacing:-.01em}
  .pills{display:flex;gap:8px;flex-wrap:wrap}
  .pill{background:var(--card);border:1px solid var(--border);border-radius:999px;padding:4px 10px;font-size:12px;color:var(--muted)}
  .pill b{color:var(--text)}
  .modes{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}
  button.mode{background:var(--card);border:1px solid var(--border);color:var(--text);border-radius:10px;padding:12px;text-align:left;cursor:pointer;transition:.15s}
  button.mode:hover{border-color:var(--acc)}
  button.mode.active{border-color:var(--acc);background:rgba(59,130,246,.14)}
  button.mode .t{font-weight:600;font-size:14px;display:block}
  button.mode .s{color:var(--muted);font-size:12px;margin-top:2px;display:block}
  .stage{background:#000;border:1px solid var(--border);border-radius:12px;overflow:hidden;position:relative;display:flex;align-items:center;justify-content:center;min-height:320px}
  .stage img{width:100%;height:auto;display:block;max-height:75vh;object-fit:contain}
  .bar{display:flex;flex-wrap:wrap;gap:8px;align-items:center;justify-content:space-between}
  .btn{background:var(--card);border:1px solid var(--border);color:var(--text);border-radius:8px;padding:8px 12px;cursor:pointer;font:inherit;text-decoration:none}
  .btn:hover{border-color:var(--acc)}
  .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:10px;background:var(--card);border:1px solid var(--border);border-radius:12px;padding:14px}
  label.ctl{display:flex;flex-direction:column;gap:4px;font-size:12px;color:var(--muted)}
  label.ctl span{display:flex;justify-content:space-between}
  label.ctl b{color:var(--text)}
  input[type=range],select,input[type=text],input[type=password]{width:100%;accent-color:var(--acc)}
  input[type=text],input[type=password],select{background:var(--bg);color:var(--text);border:1px solid var(--border);border-radius:6px;padding:6px 8px;font:inherit}
  details{background:var(--card);border:1px solid var(--border);border-radius:12px;padding:12px 14px}
  summary{cursor:pointer;font-weight:600;font-size:13px}
</style>
</head>
<body>
<div class="wrap">
  <header>
    <h1>XIAO ESP32-S3 Ultra Stream</h1>
    <div class="pills">
      <div class="pill">Sensor <b id="p-sensor">—</b></div>
      <div class="pill">Res <b id="p-res">—</b></div>
      <div class="pill">Capture <b id="p-cfps">—</b></div>
      <div class="pill">Stream <b id="p-sfps">—</b></div>
      <div class="pill">Bitrate <b id="p-kbps">—</b></div>
      <div class="pill">Temp <b id="p-temp">—</b></div>
      <div class="pill">Wi-Fi <b id="p-rssi">—</b></div>
    </div>
  </header>

  <div class="modes">
    <button class="mode" data-mode="performance" onclick="setMode('performance')">
      <span class="t">Performance</span>
      <span class="s">Max FPS &amp; lowest latency (480&times;320)</span>
    </button>
    <button class="mode" data-mode="balanced" onclick="setMode('balanced')">
      <span class="t">Balanced</span>
      <span class="s">Crisp everyday stream (1024&times;768)</span>
    </button>
    <button class="mode" data-mode="quality" onclick="setMode('quality')">
      <span class="t">Quality</span>
      <span class="s">Full sensor resolution (2048&times;1536)</span>
    </button>
  </div>

  <div class="stage">
    <img id="stream" alt="Live Stream">
  </div>

  <div class="bar">
    <div style="display:flex;gap:8px;flex-wrap:wrap">
      <a class="btn" href="/capture" target="_blank">Full Snapshot</a>
      <button class="btn" onclick="toggleFlip('vflip')">Flip V</button>
      <button class="btn" onclick="toggleFlip('hmirror')">Mirror H</button>
      <button class="btn" onclick="reconnectStream()">Reconnect</button>
    </div>
    <span style="color:var(--muted);font-size:12px" id="p-net"></span>
  </div>

  <details>
    <summary>Fine Tuning &amp; Wi-Fi Setup</summary>
    <div class="grid" style="margin-top:12px;border:none;padding:0">
      <label class="ctl"><span>JPEG Quality (lower = sharper) <b id="v-q">10</b></span>
        <input type="range" min="4" max="32" value="10" id="c-q" onchange="setParam('quality',this.value)">
      </label>
      <label class="ctl"><span>Exposure Bias <b id="v-ae">0</b></span>
        <input type="range" min="-3" max="3" value="0" id="c-ae" onchange="setParam('ae_level',this.value)">
      </label>
      <label class="ctl"><span>Sharpness <b id="v-sh">0</b></span>
        <input type="range" min="-3" max="3" value="0" id="c-sh" onchange="setParam('sharpness',this.value)">
      </label>
      <label class="ctl"><span>Denoise <b id="v-dn">2</b></span>
        <input type="range" min="0" max="8" value="2" id="c-dn" onchange="setParam('denoise',this.value)">
      </label>
      <label class="ctl"><span>Contrast <b id="v-ct">0</b></span>
        <input type="range" min="-3" max="3" value="0" id="c-ct" onchange="setParam('contrast',this.value)">
      </label>
      <label class="ctl"><span>Saturation <b id="v-sa">0</b></span>
        <input type="range" min="-4" max="4" value="0" id="c-sa" onchange="setParam('saturation',this.value)">
      </label>
    </div>
    <div style="margin-top:14px;display:flex;gap:8px;flex-wrap:wrap;align-items:center">
      <input type="text" id="w-ssid" placeholder="Wi-Fi SSID" style="max-width:220px">
      <input type="password" id="w-pass" placeholder="Wi-Fi Password" style="max-width:220px">
      <button class="btn" onclick="saveWifi()">Save Wi-Fi &amp; Reboot</button>
    </div>
  </details>
</div>
<script>
const img = document.getElementById('stream');
let lastState = {};
function reconnectStream(){
  img.src = 'http://' + location.hostname + ':81/stream?t=' + Date.now();
}
reconnectStream();
async function setMode(m){
  await fetch('/api/mode?mode=' + encodeURIComponent(m), {method:'POST'});
  poll();
}
async function setParam(k,v){
  await fetch('/api/settings?' + encodeURIComponent(k) + '=' + encodeURIComponent(v), {method:'POST'});
  poll();
}
async function toggleFlip(k){
  const nv = lastState[k] ? 0 : 1;
  await setParam(k, nv);
}
async function saveWifi(){
  const s = document.getElementById('w-ssid').value;
  const p = document.getElementById('w-pass').value;
  if(!s) return alert('Enter SSID');
  await fetch('/api/wifi?ssid=' + encodeURIComponent(s) + '&pass=' + encodeURIComponent(p), {method:'POST'});
  alert('Saved! Device rebooting...');
}
async function poll(){
  try{
    const d = await (await fetch('/api/status')).json();
    lastState = d;
    document.getElementById('p-sensor').textContent = d.sensor;
    document.getElementById('p-res').textContent = d.width + 'x' + d.height;
    document.getElementById('p-cfps').textContent = d.capture_fps.toFixed(1) + ' fps';
    document.getElementById('p-sfps').textContent = d.stream_fps.toFixed(1) + ' fps';
    document.getElementById('p-kbps').textContent = (d.tx_kbps/1000).toFixed(2) + ' Mbps';
    document.getElementById('p-temp').textContent = d.temp_c.toFixed(1) + '°C';
    document.getElementById('p-rssi').textContent = d.wifi_mode === 'AP' ? 'AP' : (d.rssi + ' dBm');
    document.getElementById('p-net').textContent = d.wifi_mode + ' · ' + d.ssid + ' · ' + d.ip + ' (TCP bin :82, MJPEG :81)';
    document.querySelectorAll('button.mode').forEach(b=>b.classList.toggle('active', b.dataset.mode===d.mode));
    document.getElementById('c-q').value = d.quality; document.getElementById('v-q').textContent = d.quality;
    document.getElementById('c-ae').value = d.ae_level; document.getElementById('v-ae').textContent = d.ae_level;
    document.getElementById('c-sh').value = d.sharpness; document.getElementById('v-sh').textContent = d.sharpness;
    document.getElementById('c-dn').value = d.denoise; document.getElementById('v-dn').textContent = d.denoise;
    document.getElementById('c-ct').value = d.contrast; document.getElementById('v-ct').textContent = d.contrast;
    document.getElementById('c-sa').value = d.saturation; document.getElementById('v-sa').textContent = d.saturation;
  }catch(e){}
}
poll();
setInterval(poll, 1000);
</script>
</body>
</html>)HTML";
