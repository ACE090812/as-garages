// Admin editor (staff only, English). Opened by /asgarage. All saves are re-validated on the server.
(() => {
  const { post, esc, sfx } = window.ASG;
  const root = document.getElementById('admin');

  const TYPES = [['public', 'Public'], ['job', 'Job'], ['gang', 'Gang'], ['private', 'Private / house'], ['impound', 'Impound lot']];
  const CLASSES = [['cars', 'Cars'], ['bikes', 'Bikes'], ['boats', 'Boats'], ['air', 'Air']];
  const S = { garages: [], sel: null, draft: null, tab: 'garages', msg: '', msgOk: true, vehicles: [], vq: '', logs: [], lq: '', saving: false };

  const clone = (o) => JSON.parse(JSON.stringify(o));
  const blank = () => ({ id: '', label: '', sub: '', type: 'public', slots: 10, radius: 3, price: 0, group: '', shared: false,
    blipOn: true, vehicleClasses: [], coords: null, spawns: [], preview: null, isNew: true });
  const fmt = (p) => (p ? `${p.x.toFixed(1)}, ${p.y.toFixed(1)}, ${p.z.toFixed(1)}${p.w !== undefined ? ` · ${Math.round(p.w)}°` : ''}` : 'Not placed');
  const say = (msg, ok = true) => { S.msg = msg || ''; S.msgOk = ok; };

  function pickGarage(id) {
    const g = S.garages.find((x) => x.id === id);
    S.sel = g ? g.id : null;
    S.draft = g ? clone(g) : null;
  }

  async function reload(keep) {
    const data = await post('adminData');
    S.garages = data.garages || [];
    pickGarage(keep || S.sel || (S.garages[0] && S.garages[0].id));
  }

  // ---- views -----------------------------------------------------------------
  const chip = (on, attr, label) => `<button type="button" class="chip${on ? ' on' : ''}" ${attr}>${esc(label)}</button>`;

  function locRow(title, p, attrs, extra = '') {
    return `<div class="loc"><div><b>${esc(title)}</b><small>${esc(fmt(p))}</small></div>
      <div class="grp">${p ? `<button type="button" class="btn sm" ${attrs.goto}>Go</button>` : ''}
      <button type="button" class="btn sm" ${attrs.place}>${p ? 'Re-place' : 'Place'}</button>${extra}</div></div>`;
  }

  function garageForm() {
    const d = S.draft;
    if (!d) return '<div class="empty">Pick a garage on the left, or create a new one.</div>';
    const grouped = d.type === 'job' || d.type === 'gang';
    const spawns = d.spawns.map((s, i) => locRow(`Spawn point ${i + 1}`, s,
      { goto: `data-goto="spawn:${i}"`, place: `data-place="spawn:${i}"` },
      `<button type="button" class="btn sm dng" data-rmspawn="${i}" aria-label="Remove spawn point ${i + 1}">×</button>`)).join('');
    const owner = d.type === 'private' && !d.isNew
      ? `<div class="loc"><div><b>Owner</b><small>${d.owner ? esc(d.ownerName || d.owner) : 'For sale'}</small></div>
          ${d.owner ? '<div class="grp"><button type="button" class="btn sm dng" data-clearowner>Clear owner</button></div>' : ''}</div>` : '';

    return `<div class="ad-cols"><div class="ad-col">
      <div><label class="lb" for="f-id">Id</label><input id="f-id" class="fld" data-f="id" type="text" value="${esc(d.id)}" ${d.isNew ? '' : 'disabled'} placeholder="e.g. legion_square"></div>
      <div class="two"><div><label class="lb" for="f-label">Name</label><input id="f-label" class="fld" data-f="label" type="text" value="${esc(d.label)}"></div>
        <div><label class="lb" for="f-sub">Subtitle</label><input id="f-sub" class="fld" data-f="sub" type="text" value="${esc(d.sub)}"></div></div>
      <div><span class="lb">Type</span><div class="chips">${TYPES.map(([k, l]) => chip(d.type === k, `data-type="${k}"`, l)).join('')}</div></div>
      <div class="two"><div><label class="lb" for="f-slots">Slots</label><input id="f-slots" class="fld" data-f="slots" data-num type="number" min="1" max="200" value="${d.slots}"></div>
        <div><label class="lb" for="f-radius">Interaction radius (m)</label><input id="f-radius" class="fld" data-f="radius" data-num type="number" min="1.5" max="10" step="0.5" value="${d.radius}"></div></div>
      ${grouped ? `<div><label class="lb" for="f-group">${d.type === 'job' ? 'Jobs' : 'Gangs'} (comma separated, name:minGrade)</label><input id="f-group" class="fld" data-f="group" type="text" value="${esc(d.group)}" placeholder="police, sheriff:2"></div>` : ''}
      ${d.type === 'private' ? `<div><label class="lb" for="f-price">Price ($)</label><input id="f-price" class="fld" data-f="price" data-num type="number" min="0" value="${d.price}"></div>` : ''}
      <div><span class="lb">Accepted vehicle classes <small style="text-transform:none;letter-spacing:0">(none selected = all)</small></span>
        <div class="chips">${CLASSES.map(([k, l]) => chip(d.vehicleClasses.includes(k), `data-class="${k}"`, l)).join('')}</div></div>
      <div><span class="lb">Options</span><div class="chips">${chip(d.blipOn, 'data-opt="blipOn"', 'Map blip')}${grouped ? chip(d.shared, 'data-opt="shared"', 'Everyone in the group sees all stored vehicles') : ''}</div></div>
      ${owner}
    </div><div class="ad-col">
      <span class="lb">Locations</span>
      ${locRow('Interaction point', d.coords, { goto: 'data-goto="coords"', place: 'data-place="coords"' })}
      ${spawns}
      <button type="button" class="btn sm" data-addspawn style="align-self:flex-start">+ Add spawn point</button>
      ${locRow('3D preview point', d.preview, { goto: 'data-goto="preview"', place: 'data-place="preview"' },
        d.preview ? '<button type="button" class="btn sm dng" data-clearpreview aria-label="Clear preview point">×</button>' : '')}
      <div class="note">Placing: the editor hides, walk or drive to the spot, press <b>E</b> to confirm or <b>Backspace</b> to cancel.
        Sit in a vehicle to capture its heading (best for spawn bays). Boats and aircraft need their own bays on water or a helipad.</div>
    </div></div>`;
  }

  function vehiclesView() {
    const opts = S.garages.filter((g) => g.type !== 'impound').map((g) => `<option value="${esc(g.id)}">${esc(g.label)}</option>`).join('');
    const rows = S.vehicles.map((v) => `<tr><td class="mono">${esc(v.plate)}</td><td>${esc(v.model)}${v.nick ? ` <small>(${esc(v.nick)})</small>` : ''}</td>
      <td>${esc(v.owner)}</td><td>${esc(v.state)}</td><td>${esc(v.garage)}</td>
      <td><button type="button" class="btn sm" data-force="${esc(v.plate)}">Return to garage</button></td></tr>`).join('');
    return `<div style="display:flex;gap:12px;margin-bottom:14px"><input class="fld" id="vq" type="text" placeholder="Search plate or owner id" value="${esc(S.vq)}" style="flex:1">
        <select class="fld" id="vgarage" style="width:260px" aria-label="Garage to return to">${opts}</select></div>
      <table class="tbl"><thead><tr><th>Plate</th><th>Model</th><th>Owner</th><th>State</th><th>Garage</th><th></th></tr></thead><tbody>${rows}</tbody></table>
      ${S.vehicles.length ? '' : '<div class="empty">No vehicles found.</div>'}`;
  }

  function logsView() {
    const rows = S.logs.map((l) => `<div class="logrow"><span>${esc(new Date(l.ts * 1000).toLocaleString())}</span><span>${esc(l.action)}</span><span class="mono">${esc(l.plate || '')}</span><span>${esc(l.detail || '')}</span></div>`).join('');
    return `<div style="margin-bottom:14px"><input class="fld" id="lq" type="text" placeholder="Filter by action, plate or text" value="${esc(S.lq)}"></div>
      ${rows || '<div class="empty">No log entries.</div>'}`;
  }

  function render() {
    const keepScroll = root.querySelector('.ad-body')?.scrollTop || 0;
    const list = S.garages.map((g) => `<button type="button" class="gl${S.sel === g.id && S.draft && !S.draft.isNew ? ' on' : ''}" data-g="${esc(g.id)}">
      <b>${esc(g.label)}</b><small>${esc(g.type)} · ${g.slots} slots${g.override ? (g.inConfig ? ' · edited' : '') : ' · config.lua'}</small></button>`).join('');
    const d = S.draft;
    const canDelete = d && !d.isNew && d.override;
    const body = S.tab === 'garages' ? garageForm() : S.tab === 'vehicles' ? vehiclesView() : logsView();

    root.innerHTML = `<aside class="ad-side"><div class="hd" style="font-size:28px;font-weight:700;line-height:1">Garages</div>
        <button type="button" class="btn pri" data-new>+ New garage</button><div class="ad-list">${list}</div></aside>
      <section class="ad-main"><div class="ad-head"><div class="ad-tabs">
          ${['garages', 'vehicles', 'logs'].map((t) => `<button type="button" class="seg${S.tab === t ? ' on' : ''}" data-tab="${t}">${t[0].toUpperCase() + t.slice(1)}</button>`).join('')}</div>
        <div style="display:flex;gap:10px;align-items:center">
          ${S.tab === 'garages' && d ? `${canDelete ? `<button type="button" class="btn dng" data-delete>${d.inConfig ? 'Reset to config' : 'Delete garage'}</button>` : ''}
            <button type="button" class="btn pri" data-save ${S.saving ? 'disabled' : ''}>${S.saving ? 'Saving…' : 'Save changes'}</button>` : ''}
          <button type="button" class="btn" data-close>Close</button></div></div>
        ${S.msg ? `<div class="msg" role="status" style="color:${S.msgOk ? 'var(--ok)' : 'var(--bad)'}">${esc(S.msg)}</div>` : ''}
        <div class="ad-body">${body}</div></section>`;
    const bodyEl = root.querySelector('.ad-body');
    if (bodyEl) bodyEl.scrollTop = keepScroll;
  }

  // ---- actions ---------------------------------------------------------------
  async function place(spec) {
    const d = S.draft;
    if (!d) return;
    const [kind, idx] = spec.split(':');
    const label = kind === 'coords' ? 'interaction point' : kind === 'preview' ? 'preview point' : `spawn point ${Number(idx) + 1}`;
    const res = await post('adminPlace', { label });
    if (res.cancel) return;
    if (kind === 'coords') d.coords = { x: res.x, y: res.y, z: res.z };
    else if (kind === 'preview') d.preview = res;
    else d.spawns[Number(idx)] = res;
    render();
  }

  function goto(spec) {
    const d = S.draft;
    const [kind, idx] = spec.split(':');
    const p = kind === 'coords' ? d.coords : kind === 'preview' ? d.preview : d.spawns[Number(idx)];
    if (p) post('adminGoto', p);
  }

  async function save() {
    const d = S.draft;
    if (!d) return;
    S.saving = true; say(''); render();
    const res = await post('adminSave', {
      id: d.id, label: d.label, sub: d.sub, type: d.type, slots: d.slots, radius: d.radius, price: d.price, group: d.group,
      shared: d.shared, blipOn: d.blipOn, vehicleClasses: d.vehicleClasses, coords: d.coords, spawns: d.spawns, preview: d.preview,
    });
    S.saving = false;
    say(res.msg, !!res.ok);
    if (res.ok) { sfx('confirm'); await reload(d.id.toLowerCase()); } else sfx('error');
    render();
  }

  async function loadVehicles() { S.vehicles = await post('adminVehicles', { query: S.vq }); render(); }
  async function loadLogs() { S.logs = await post('adminLogs', { query: S.lq }); render(); }

  // CEF swallows window.confirm(), so destructive buttons ask for a second click instead.
  let armed = null;
  function confirmTwice(key, btn, text) {
    if (armed === key) { armed = null; return true; }
    armed = key;
    btn.textContent = text;
    setTimeout(() => { if (armed === key) { armed = null; render(); } }, 4000);
    return false;
  }

  let timer;
  const debounce = (fn) => { clearTimeout(timer); timer = setTimeout(fn, 300); };

  root.addEventListener('input', (e) => {
    const t = e.target, d = S.draft;
    if (t.id === 'vq') { S.vq = t.value; debounce(async () => { S.vehicles = await post('adminVehicles', { query: S.vq }); const p = root.querySelector('.ad-body'); if (p) { const keep = t.selectionStart; render(); const el = root.querySelector('#vq'); el.focus(); el.setSelectionRange(keep, keep); } }); return; }
    if (t.id === 'lq') { S.lq = t.value; debounce(async () => { S.logs = await post('adminLogs', { query: S.lq }); const keep = t.selectionStart; render(); const el = root.querySelector('#lq'); el.focus(); el.setSelectionRange(keep, keep); }); return; }
    if (d && t.dataset.f) d[t.dataset.f] = t.hasAttribute('data-num') ? Number(t.value) : t.value;
  });

  root.addEventListener('click', async (e) => {
    const b = e.target.closest('button');
    if (!b) return;
    const d = S.draft;
    const ds = b.dataset;

    if ('close' in ds) { post('close'); return; }
    if (ds.tab) {
      sfx('select'); S.tab = ds.tab; say('');
      if (ds.tab === 'vehicles') await loadVehicles(); else if (ds.tab === 'logs') await loadLogs(); else render();
      return;
    }
    if (ds.g) { sfx('select'); S.tab = 'garages'; say(''); pickGarage(ds.g); render(); return; }
    if ('new' in ds) { sfx('select'); S.tab = 'garages'; say(''); S.sel = null; S.draft = blank(); render(); return; }
    if ('save' in ds) { await save(); return; }
    if ('delete' in ds && d) {
      if (!confirmTwice('delete', b, 'Click again to confirm')) return;
      const res = await post('adminDelete', { id: d.id });
      say(res.msg, !!res.ok);
      if (res.ok) await reload(d.inConfig ? d.id : null);
      render();
      return;
    }
    if ('clearowner' in ds && d) {
      if (!confirmTwice('owner', b, 'Click again: members lose access')) return;
      const res = await post('adminClearOwner', { id: d.id });
      say(res.msg, !!res.ok);
      if (res.ok) await reload(d.id);
      render();
      return;
    }
    if (ds.force) {
      const garage = root.querySelector('#vgarage')?.value;
      const res = await post('adminForce', { plate: ds.force, garage });
      say(res.msg, !!res.ok);
      await loadVehicles();
      return;
    }
    if (!d) return;
    if (ds.type) { d.type = ds.type; if (d.type === 'private') d.shared = true; render(); }
    else if (ds.class) { const i = d.vehicleClasses.indexOf(ds.class); if (i >= 0) d.vehicleClasses.splice(i, 1); else d.vehicleClasses.push(ds.class); render(); }
    else if (ds.opt) { d[ds.opt] = !d[ds.opt]; render(); }
    else if ('addspawn' in ds) { await place(`spawn:${d.spawns.length}`); }
    else if (ds.rmspawn !== undefined) { d.spawns.splice(Number(ds.rmspawn), 1); render(); }
    else if ('clearpreview' in ds) { d.preview = null; render(); }
    else if (ds.place) { await place(ds.place); }
    else if (ds.goto) { goto(ds.goto); }
  });

  window.ASGAdmin = {
    open(data) {
      S.garages = data.garages || [];
      S.tab = 'garages'; S.msg = ''; S.vq = ''; S.lq = '';
      pickGarage(S.garages[0] && S.garages[0].id);
      render();
    },
  };
})();
