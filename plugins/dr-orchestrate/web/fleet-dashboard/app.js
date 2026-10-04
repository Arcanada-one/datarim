// app.js — Fleet Dashboard frontend: polls /fleet-graph.json and renders
// a force-directed graph (canvas-based, no external dependencies).

const POLL_INTERVAL_MS = 30000;
const STALE_THRESHOLD_MS = 90000; // 3 missed polls = stale

let lastFetch = 0;
let graphData = { nodes: [], edges: [], metrics: {} };

// ── DOM refs ──────────────────────────────────────────────────────────────────

const canvas = document.getElementById('graph-canvas');
const ctx = canvas.getContext('2d');
const statusDot = document.getElementById('status-dot');
const lastUpdated = document.getElementById('last-updated');
const errorBar = document.getElementById('error-bar');
const mTotal = document.getElementById('m-total');
const mAgents = document.getElementById('m-agents');
const mSource = document.getElementById('m-source');
const agentsTbody = document.getElementById('agents-tbody');

// ── canvas resize ─────────────────────────────────────────────────────────────

function resizeCanvas() {
  const container = canvas.parentElement;
  canvas.width = container.clientWidth;
  canvas.height = container.clientHeight;
  drawGraph();
}

window.addEventListener('resize', resizeCanvas);

// ── force-directed layout (simple Verlet) ────────────────────────────────────

const NODE_RADIUS = 10;
let positions = {};
let velocities = {};

function initPositions(nodes) {
  nodes.forEach((node, i) => {
    if (!positions[node.id]) {
      const angle = (2 * Math.PI * i) / Math.max(nodes.length, 1);
      const r = Math.min(canvas.width, canvas.height) * 0.3;
      positions[node.id] = {
        x: canvas.width / 2 + r * Math.cos(angle),
        y: canvas.height / 2 + r * Math.sin(angle),
      };
      velocities[node.id] = { x: 0, y: 0 };
    }
  });
}

function applyForces(nodes, edges) {
  const k = 80; // spring rest length
  const repulsion = 3000;
  const damping = 0.85;

  // Repulsion between all node pairs
  for (let i = 0; i < nodes.length; i++) {
    for (let j = i + 1; j < nodes.length; j++) {
      const a = positions[nodes[i].id];
      const b = positions[nodes[j].id];
      if (!a || !b) continue;
      const dx = a.x - b.x;
      const dy = a.y - b.y;
      const dist = Math.max(Math.sqrt(dx * dx + dy * dy), 1);
      const force = repulsion / (dist * dist);
      velocities[nodes[i].id].x += (dx / dist) * force;
      velocities[nodes[i].id].y += (dy / dist) * force;
      velocities[nodes[j].id].x -= (dx / dist) * force;
      velocities[nodes[j].id].y -= (dy / dist) * force;
    }
  }

  // Spring attraction along edges
  edges.forEach(edge => {
    const a = positions[edge.from];
    const b = positions[edge.to];
    if (!a || !b) return;
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const dist = Math.max(Math.sqrt(dx * dx + dy * dy), 1);
    const force = (dist - k) * 0.05;
    velocities[edge.from].x += (dx / dist) * force;
    velocities[edge.from].y += (dy / dist) * force;
    velocities[edge.to].x -= (dx / dist) * force;
    velocities[edge.to].y -= (dy / dist) * force;
  });

  // Apply velocities with damping and boundary clamp
  nodes.forEach(node => {
    const pos = positions[node.id];
    const vel = velocities[node.id];
    if (!pos || !vel) return;
    vel.x *= damping;
    vel.y *= damping;
    pos.x = Math.max(NODE_RADIUS, Math.min(canvas.width - NODE_RADIUS, pos.x + vel.x));
    pos.y = Math.max(NODE_RADIUS, Math.min(canvas.height - NODE_RADIUS, pos.y + vel.y));
  });
}

// ── draw ──────────────────────────────────────────────────────────────────────

function drawGraph() {
  ctx.clearRect(0, 0, canvas.width, canvas.height);

  const nodes = graphData.nodes || [];
  const edges = graphData.edges || [];

  if (nodes.length === 0) {
    ctx.fillStyle = '#8b949e';
    ctx.font = '14px system-ui';
    ctx.textAlign = 'center';
    ctx.fillText('No agents in fleet', canvas.width / 2, canvas.height / 2);
    return;
  }

  initPositions(nodes);
  applyForces(nodes, edges);

  // Draw edges
  edges.forEach(edge => {
    const a = positions[edge.from];
    const b = positions[edge.to];
    if (!a || !b) return;
    ctx.beginPath();
    ctx.moveTo(a.x, a.y);
    ctx.lineTo(b.x, b.y);
    ctx.strokeStyle = '#30363d';
    ctx.lineWidth = 1;
    ctx.stroke();
  });

  // Draw nodes
  nodes.forEach(node => {
    const pos = positions[node.id];
    if (!pos) return;
    const color = node.active ? '#3fb950' : '#6e7681';
    ctx.beginPath();
    ctx.arc(pos.x, pos.y, NODE_RADIUS, 0, 2 * Math.PI);
    ctx.fillStyle = color;
    ctx.fill();
    ctx.fillStyle = '#f0f6fc';
    ctx.font = '10px system-ui';
    ctx.textAlign = 'center';
    ctx.fillText(node.id.length > 10 ? node.id.slice(0, 10) + '…' : node.id,
      pos.x, pos.y + NODE_RADIUS + 12);
  });
}

// ── metrics panel ─────────────────────────────────────────────────────────────

function updateMetrics(data) {
  const m = data.metrics || {};
  mTotal.textContent = m.total_messages ?? '—';
  mAgents.textContent = m.active_agents ?? (data.nodes || []).length;
  mSource.textContent = m.snapshot_source ?? '—';

  const nodes = data.nodes || [];
  agentsTbody.innerHTML = nodes.map(n => `
    <tr>
      <td title="${n.id}">${n.id.length > 14 ? n.id.slice(0, 14) + '…' : n.id}</td>
      <td>${n.role || '—'}</td>
      <td><span class="badge ${n.active ? 'active' : 'inactive'}">${n.active ? 'active' : 'idle'}</span></td>
    </tr>
  `).join('') || '<tr><td colspan="3" style="color:#8b949e;padding:8px">No agents</td></tr>';
}

// ── fetch + poll ──────────────────────────────────────────────────────────────

function setError(msg) {
  errorBar.style.display = msg ? 'block' : 'none';
  errorBar.textContent = msg || '';
}

async function fetchGraph() {
  try {
    const res = await fetch('/fleet-graph.json?t=' + Date.now());
    if (!res.ok) throw new Error('HTTP ' + res.status);
    const data = await res.json();
    graphData = data;
    lastFetch = Date.now();
    setError(null);
    const ts = data.generated_at || new Date().toISOString();
    lastUpdated.textContent = 'Updated ' + ts.replace('T', ' ').slice(0, 19) + ' UTC';
    updateMetrics(data);
    drawGraph();
  } catch (err) {
    setError('Failed to fetch fleet-graph.json: ' + err.message);
  }

  // Mark stale if last fetch is too old
  const age = Date.now() - lastFetch;
  statusDot.classList.toggle('stale', lastFetch > 0 && age > STALE_THRESHOLD_MS);
}

// ── animation loop ────────────────────────────────────────────────────────────

let animFrame;
function animate() {
  if ((graphData.nodes || []).length > 0) {
    applyForces(graphData.nodes || [], graphData.edges || []);
    drawGraph();
  }
  animFrame = requestAnimationFrame(animate);
}

// ── init ──────────────────────────────────────────────────────────────────────

resizeCanvas();
fetchGraph();
setInterval(fetchGraph, POLL_INTERVAL_MS);
animate();
