(() => {
  const $ = (id) => document.getElementById(id);
  const app = $('app');
  const root = document.documentElement;
  const state = {
    view: null, data: null, t: {}, sel: null, q: '', folder: '', ownerRelease: true, sounds: true, modal: null, t0: 0,
    cam: 'front', preview: { spin: true, lights: true }, theme: { mode: 'dark', accent: '#A594FF' },
  };

  const post = (name, body) =>
    fetch(`https://${window.GetParentResourceName ? GetParentResourceName() : 'as-garages'}/${name}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}),
    }).then((r) => r.json()).catch(() => ({}));
  const sfx = (kind) => { if (state.sounds) post('sfx', { kind }); };

  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  // tr('slots_of', 3, 10) fills each %s in order
  const tr = (key, ...args) => { let i = 0; return String(state.t[key] ?? key).replace(/%s/g, () => args[i++] ?? ''); };
  const money = (n) => Number(n || 0).toLocaleString('en-US');
  const col = (n) => (n >= 70 ? 'var(--ok)' : n >= 40 ? 'var(--warn)' : 'var(--bad)');
  const STATUS = {
    in: ['status_in', 'var(--ok)'], out: ['status_out', 'var(--warn)'], imp: ['status_imp', 'var(--bad)'],
    away: ['status_away', 'var(--muted)'], transit: ['status_transit', 'var(--accent-text)'],
  };
  const CAMS = ['front', 'side', 'rear', 'cabin', 'engine', 'wheel'];
  const nowSec = () => state.data.now + (Date.now() - state.t0) / 1000;

  window.ASG = { post, esc, sfx, state };

  // ---- theme ---------------------------------------------------------------
  const SUN = '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>';
  const MOON = '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M21 12.8A9 9 0 1111.2 3a7 7 0 009.8 9.8z"/></svg>';

  function applyTheme(mode, accent) {
    const m = /^#?([0-9a-f]{6})$/i.exec(accent || '');
    const n = parseInt((m ? m[1] : 'A594FF'), 16);
    const [r, g, b] = [(n >> 16) & 255, (n >> 8) & 255, n & 255];
    const lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
    const dark = [r, g, b].map((c) => Math.round(c * 0.55)).join(',');
    state.theme = { mode, accent };
    root.dataset.theme = mode;
    root.style.setProperty('--accent', `rgb(${r},${g},${b})`);
    root.style.setProperty('--accent-ink', lum > 0.55 ? '#140F2E' : '#FFFFFF');
    root.style.setProperty('--accent-text', mode === 'light' ? `rgb(${dark})` : `rgb(${r},${g},${b})`);
    root.style.setProperty('--accent-soft', `rgba(${r},${g},${b},.16)`);
    $('themebtn').innerHTML = mode === 'light' ? MOON : SUN;
  }
  const savedMode = () => { try { return localStorage.getItem('asg_mode'); } catch (e) { return null; } };
  $('themebtn').addEventListener('click', () => {
    const mode = state.theme.mode === 'light' ? 'dark' : 'light';
    try { localStorage.setItem('asg_mode', mode); } catch (e) { /* storage can be unavailable */ }
    applyTheme(mode, state.theme.accent);
    sfx('select');
  });

  function fit() {
    const s = Math.min(innerWidth / 1920, innerHeight / 1080);
    app.style.transform = `translate(${(innerWidth - 1920 * s) / 2}px, ${(innerHeight - 1080 * s) / 2}px) scale(${s})`;
  }
  addEventListener('resize', fit);
  fit();

  // ---- formatting ------------------------------------------------------------
  function dur(sec) {
    sec = Math.max(0, Math.floor(sec));
    const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
    const p = (n) => String(n).padStart(2, '0');
    return h > 0 ? `${h}:${p(m)}:${p(s)}` : `${p(m)}:${p(s)}`;
  }
  function since(epoch) {
    if (!epoch) return tr('never');
    const days = Math.floor((nowSec() - epoch) / 86400);
    return days <= 0 ? tr('today') : days === 1 ? tr('yesterday') : tr('days_ago', days);
  }

  const list = () => {
    const q = state.q.trim().toLowerCase();
    return (state.data?.vehicles || [])
      .filter((v) => (!q || v.name.toLowerCase().includes(q) || v.plate.toLowerCase().includes(q)) && (!state.folder || v.folder === state.folder))
      .sort((a, b) => Number(b.fav) - Number(a.fav));
  };
  const current = () => (state.data?.vehicles || []).find((v) => v.plate === state.sel);
  const folders = () => [...new Set((state.data?.vehicles || []).map((v) => v.folder).filter(Boolean))].sort();

  // ---- main screen -----------------------------------------------------------
  function renderTop() {
    const g = state.data.garage;
    const isLot = state.view === 'impound';
    const d = state.data;
    const manage = d.isOwner ? `<button class="pill" type="button" data-act="access">${esc(tr('manage_access'))}</button>` : '';
    const upgrade = d.upgrade ? `<button class="pill" type="button" data-act="upgrade">${esc(tr('upgrade_btn', d.upgrade.per, money(d.upgrade.price)))}</button>` : '';
    $('titleblock').innerHTML = `<h1 class="hd">${esc(g.label)}</h1><div class="sub"><span>${esc(g.sub || '')}</span>
      <span class="pill">${isLot ? tr('lot_sub', d.vehicles.length) : tr('slots_of', g.used, g.slots)}</span>${manage}${upgrade}</div>`;
    const tabLabel = { mine: 'tab_mine', job: 'tab_job', gang: 'tab_gang', private: 'tab_private', impound: 'tab_impound' }[d.tab] || 'tab_mine';
    $('tabs').innerHTML = `<button class="seg on" type="button">${esc(tr(tabLabel))}</button>`;
    $('search').placeholder = tr('search');
    $('hints').innerHTML = `<span><b>←→</b> ${esc(tr('h_browse'))}</span><span><b>Enter</b> ${esc(tr('h_select'))}</span><span><b>1-6</b> ${esc(tr('h_camera'))}</span><span><b>Esc</b> ${esc(tr('h_close'))}</span>`;
  }

  function renderFolders() {
    const fs = folders();
    const el = $('folders');
    el.hidden = fs.length === 0;
    if (!fs.length) return;
    const chip = (name, label) => `<button type="button" class="chip${state.folder === name ? ' on' : ''}" data-folder="${esc(name)}">${esc(label)}</button>`;
    el.innerHTML = chip('', tr('folder_all')) + fs.map((f) => chip(f, f)).join('');
  }

  function renderCamera() {
    const modeBtns = CAMS.map((c, i) => `<button type="button" class="chip${state.cam === c ? ' on' : ''}" data-cam="${c}" title="${i + 1}">${esc(tr('cam_' + c))}</button>`).join('');
    const opt = (k, label) => `<button type="button" class="chip${state.preview[k] ? ' on' : ''}" data-popt="${k}">${esc(label)}</button>`;
    $('camera').innerHTML = `${modeBtns}<span class="sep"></span>${opt('spin', tr('opt_spin'))}${opt('lights', tr('opt_lights'))}`;
  }

  function renderStrip() {
    const items = list();
    $('strip').innerHTML = items.length ? items.map((v, i) => {
      const [k, c] = STATUS[v.status] || STATUS.in;
      return `<button type="button" class="vcard${v.plate === state.sel ? ' sel' : ''}" data-plate="${esc(v.plate)}" style="animation-delay:${i * 45}ms">
        <div class="n">${v.fav ? '★ ' : ''}${esc(v.name)}</div>
        <div class="m"><span class="p">${esc(v.plate)}</span><span class="dot" style="color:${c}">${esc(tr(k))}</span></div>
        <div class="f"><div class="bar"><i style="width:${v.fuel}%"></i></div><span>${v.fuel}%</span></div></button>`;
    }).join('') : `<div class="empty">${esc(tr('no_match'))}</div>`;
  }

  function primary(v) {
    const lot = state.view === 'impound';
    if (!lot) {
      if (v.status === 'in') return { label: tr('take_out'), act: 'takeOut' };
      if (v.status === 'out') return { label: tr('locate'), act: 'locate' };
      if (v.status === 'transit') return { label: tr('arrives_in', dur(v.arrive - nowSec())), disabled: true };
      if (v.status === 'away') return { label: tr('stored_at', v.at || '?'), disabled: true };
      return { label: tr('status_imp'), disabled: true };
    }
    const i = v.imp, total = i.fee + i.storage, left = i.until_ - nowSec();
    if (state.data.officer) return { label: tr('release'), act: 'retrieve' };
    if (!i.ownerRelease) return { label: tr('officers_hold'), disabled: true };
    if (left > 0) return { label: tr('held_for', dur(left)), disabled: true };
    return { label: total > 0 ? tr('pay_retrieve', money(total)) : tr('retrieve_free'), act: 'retrieve' };
  }

  function renderDetail() {
    const v = current();
    const el = $('detail');
    if (!v) { el.innerHTML = `<div class="empty">${esc(tr('no_match'))}</div>`; return; }
    const lot = state.view === 'impound';
    const a = primary(v);
    const f = state.data.features || {};
    const stat = (k, n) => `<div class="stat"><div class="l"><span>${esc(tr(k))}</span><span>${n}%</span></div><div class="bar"><i style="width:${n}%;background:${col(n)}"></i></div></div>`;
    let body;
    if (lot) {
      const i = v.imp;
      body = `<div class="info">
          <div class="kv"><span>${esc(tr('impounded_by'))}</span><span>${esc(i.by || '—')}</span></div>
          <div class="kv"><span>${esc(tr('date'))}</span><span>${esc(new Date(i.at * 1000).toLocaleString())}</span></div>
          <div class="kv" style="flex-direction:column;gap:4px"><span>${esc(tr('reason'))}</span><span style="text-align:left;font-weight:500">${esc(i.reason || '—')}</span></div></div>
        <div class="info">
          <div class="kv"><span>${esc(tr('impound_fee'))}</span><span>$${money(i.fee)}</span></div>
          <div class="kv"><span>${esc(tr('storage_fee', i.days))}</span><span>$${money(i.storage)}</span></div><hr>
          <div class="kv" style="align-items:baseline"><span>${esc(tr('total'))}</span><span class="total">$${money(i.fee + i.storage)}</span></div></div>`;
    } else {
      body = `<div style="display:flex;flex-direction:column;gap:16px">${stat('fuel', v.fuel)}${stat('engine', v.eng)}${stat('body', v.body)}</div>
        <div class="tiles"><div class="tile"><small>${esc(tr('mileage'))}</small><b>${money(v.km)} km</b></div>
        <div class="tile"><small>${esc(tr('last_stored'))}</small><b>${esc(since(v.storedAt))}</b></div></div>`;
    }
    const canMove = v.mine && v.status === 'in';
    const btn = (act, label, ok) => `<button class="btn" type="button" data-act="${act}" ${ok ? '' : 'disabled'}>${esc(label)}</button>`;
    const repair = f.repair && v.mine && v.status === 'in' && v.repair > 0
      ? `<button class="btn" type="button" data-act="repair">${esc(tr('repair_btn', money(v.repair)))}</button>` : '';
    el.innerHTML = `<div class="row"><div><div class="cls">${esc(v.cls)}</div><h2 class="hd">${esc(v.name)}</h2></div>
        ${lot || !v.mine ? '' : `<button class="btn iconbtn" type="button" data-act="fav" aria-label="${esc(tr('h_fav'))}" style="color:${v.fav ? 'var(--accent-text)' : 'var(--text)'}">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="${v.fav ? 'currentColor' : 'none'}" stroke="currentColor" stroke-width="2" stroke-linejoin="round" aria-hidden="true"><path d="M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9z"/></svg></button>`}</div>
      <div class="plate pi-${Number(v.plateIndex) || 0}">${esc(v.plate)}</div>${body}
      <div class="actions"><button class="btn pri big" type="button" ${a.disabled ? 'disabled' : `data-act="${a.act}"`}>${esc(a.label)}</button>
        ${lot ? '' : `<div class="three">${btn('transfer', tr('transfer'), canMove)}${btn('rename', tr('rename'), v.mine)}${btn('sell', tr('sell'), canMove)}</div>
          <div class="three">${btn('folder', tr('folder'), v.mine)}${btn('history', tr('history'), v.mine)}${btn('keys', tr('share_keys'), v.mine && v.status === 'out' && f.keys)}</div>${repair}`}</div>`;
  }

  function renderAll() { renderTop(); renderFolders(); renderCamera(); renderStrip(); renderDetail(); }

  function select(plate) {
    state.sel = plate;
    renderStrip();
    renderDetail();
    post('preview', { plate });
  }

  function step(dir) {
    const items = list();
    if (!items.length) return;
    const i = Math.max(0, items.findIndex((v) => v.plate === state.sel));
    const next = items[(i + dir + items.length) % items.length];
    sfx('select');
    select(next.plate);
    document.querySelector('.vcard.sel')?.scrollIntoView({ block: 'nearest', inline: 'center', behavior: 'smooth' });
  }

  function setCam(mode) {
    if (!CAMS.includes(mode)) return;
    state.cam = mode;
    sfx('select');
    post('camera', { mode });
    renderCamera();
  }

  // ---- modals ------------------------------------------------------------------------
  const evIcon = { sold: 'hist_sold', impounded: 'hist_impounded', retrieved: 'hist_retrieved', lost: 'hist_lost', abandoned: 'hist_abandoned', repaired: 'hist_repaired' };

  function renderModal() {
    const m = state.modal, v = current();
    if (!m || (!v && m.kind !== 'upgrade')) { $('modal').hidden = true; return; }
    const head = (title) => `<div><h2 class="mh hd">${esc(title)}</h2><div class="msub">${esc(v ? `${v.name} · ${v.plate}` : state.data.garage.label)}</div></div>`;
    const buttons = (label, enabled = true) => `<div class="btns"><button type="button" class="btn" data-m="cancel" ${m.busy ? 'disabled' : ''}>${esc(tr('cancel'))}</button>
      <button type="button" class="btn pri" data-m="save" ${enabled && !m.busy ? '' : 'disabled'}>${esc(label)}</button></div>`;
    const pickList = (items, selected, empty) => items.length
      ? items.map((p) => `<button type="button" class="opt${selected === p.id ? ' on' : ''}" data-pick="${esc(p.id)}"><span>${esc(p.label)}</span><small>${esc(p.note || '')}</small></button>`).join('')
      : `<div class="empty">${esc(empty)}</div>`;
    let inner = '';

    if (m.kind === 'rename') {
      inner = `${head(tr('rename_title'))}
        <div><label class="lb" for="m-name">${esc(tr('rename_label'))}</label><input id="m-name" class="fld" type="text" maxlength="24" value="${esc(v.nick || '')}"></div>${buttons(tr('save'))}`;
    } else if (m.kind === 'folder') {
      const chips = folders().map((f) => `<button type="button" class="chip${(m.name || '') === f ? ' on' : ''}" data-fpick="${esc(f)}">${esc(f)}</button>`).join('');
      inner = `${head(tr('folder_title'))}
        <div><label class="lb" for="m-folder">${esc(tr('folder_label'))}</label><input id="m-folder" class="fld" type="text" maxlength="20" value="${esc(m.name ?? v.folder ?? '')}">
        ${chips ? `<div class="chips" style="margin-top:10px">${chips}</div>` : ''}</div>${buttons(tr('save'))}`;
    } else if (m.kind === 'history') {
      const h = m.history;
      const events = h && h.events && h.events.length ? h.events.map((e) => `<div class="logrow2"><span>${esc(new Date(e.ts * 1000).toLocaleDateString())}</span>
        <span><b>${esc(tr(evIcon[e.action] || 'hist_other'))}</b><br><small>${esc(e.detail || '')}</small></span></div>`).join('') : `<div class="empty">${esc(tr('hist_empty'))}</div>`;
      inner = `${head(tr('history_title'))}
        <div class="tiles"><div class="tile"><small>${esc(tr('hist_owners'))}</small><b>${h ? h.owners : '…'}</b></div><div class="tile"><small>${esc(tr('hist_impounds'))}</small><b>${h ? h.impounds : '…'}</b></div></div>
        <div class="opts">${h ? events : `<div class="empty">…</div>`}</div>
        <div class="btns"><button type="button" class="btn pri" data-m="cancel">${esc(tr('close'))}</button></div>`;
    } else if (m.kind === 'transfer') {
      const delayNote = m.targets[0] && m.targets[0].delay > 0 ? `<div class="msub">${esc(tr('transfer_delay', Math.ceil(m.targets[0].delay / 60)))}</div>` : '';
      inner = `${head(tr('transfer_title'))}<div class="opts" role="listbox">${pickList(m.targets.map((t) => ({ id: t.id, label: t.label, note: t.fee > 0 ? '$' + money(t.fee) : '' })), m.pick, tr('no_targets'))}</div>${delayNote}
        ${buttons(tr('confirm_move'), !!m.pick)}`;
    } else if (m.kind === 'sell') {
      inner = `${head(tr('sell_title'))}
        <div><span class="lb">${esc(tr('sell_buyer'))}</span><div class="opts">${pickList(m.nearby, m.buyer, tr('no_nearby'))}</div></div>
        <div><label class="lb" for="m-price">${esc(tr('sell_price'))}</label><input id="m-price" class="fld" type="number" min="0" value="${esc(m.price)}"><div class="msub">${esc(tr('sell_hint'))}</div></div>
        ${buttons(m.busy ? tr('waiting_buyer') : tr('sell_confirm'), !!m.buyer)}`;
    } else if (m.kind === 'keys') {
      inner = `${head(tr('keys_title'))}
        <div><span class="lb">${esc(tr('sell_buyer'))}</span><div class="opts">${pickList(m.nearby, m.buyer, tr('no_nearby'))}</div><div class="msub">${esc(tr('keys_hint', state.data.features.keysMinutes))}</div></div>
        ${buttons(tr('keys_send'), !!m.buyer)}`;
    } else if (m.kind === 'repair') {
      inner = `${head(tr('repair_title'))}<div class="info"><div class="kv"><span>${esc(tr('engine'))}</span><span>${v.eng}% → 100%</span></div><div class="kv"><span>${esc(tr('body'))}</span><span>${v.body}% → 100%</span></div><hr>
        <div class="kv" style="align-items:baseline"><span>${esc(tr('total'))}</span><span class="total">$${money(v.repair)}</span></div></div>${buttons(tr('repair_confirm'))}`;
    } else if (m.kind === 'upgrade') {
      const u = state.data.upgrade;
      inner = `${head(tr('upgrade_title'))}<div class="info"><div class="kv"><span>${esc(tr('upgrade_now'))}</span><span>${state.data.garage.slots}</span></div>
        <div class="kv"><span>${esc(tr('upgrade_after'))}</span><span>${state.data.garage.slots + (u ? u.per : 0)}</span></div><hr>
        <div class="kv" style="align-items:baseline"><span>${esc(tr('total'))}</span><span class="total">$${money(u ? u.price : 0)}</span></div></div>${buttons(tr('upgrade_confirm'))}`;
    }
    $('modalbox').innerHTML = inner;
    $('modal').hidden = false;
    const focus = $('m-name') || $('m-folder') || $('m-price');
    if (focus && !m.focused) { focus.focus(); focus.select?.(); m.focused = true; }
  }

  async function openModal(kind) {
    state.modal = { kind, targets: [], nearby: [], pick: null, buyer: null, price: '0', busy: false, focused: false, name: undefined, history: null };
    sfx('confirm');
    renderModal();
    if (kind === 'transfer') state.modal.targets = await post('targets');
    if (kind === 'sell' || kind === 'keys') state.modal.nearby = await post('nearby');
    if (kind === 'history') { const v = current(); state.modal.history = await post('history', { plate: v.plate }); }
    renderModal();
  }
  function closeModal() { state.modal = null; $('modal').hidden = true; }

  $('modalbox').addEventListener('input', (e) => {
    if (state.modal && e.target.id === 'm-folder') state.modal.name = e.target.value;
  });

  $('modalbox').addEventListener('click', async (e) => {
    const m = state.modal, v = current();
    if (!m) return;
    const fp = e.target.closest('[data-fpick]');
    if (fp) { sfx('select'); m.name = fp.dataset.fpick; renderModal(); return; }
    const pick = e.target.closest('[data-pick]');
    if (pick) {
      sfx('select');
      if (m.kind === 'transfer') m.pick = pick.dataset.pick;
      else { if ($('m-price')) m.price = $('m-price').value; m.buyer = Number(pick.dataset.pick); }
      renderModal();
      return;
    }
    const b = e.target.closest('[data-m]');
    if (!b || b.disabled) return;
    if (b.dataset.m === 'cancel') { sfx('back'); closeModal(); return; }

    const finish = (res) => { if (res.ok) { sfx('confirm'); closeModal(); renderAll(); } else { m.busy = false; renderModal(); } return res.ok; };
    if (m.kind === 'rename') {
      const res = await post('rename', { plate: v.plate, name: $('m-name').value });
      if (res.ok) { v.nick = res.nick || null; v.name = res.name; v.cls = res.cls; }
      finish(res);
    } else if (m.kind === 'folder') {
      const res = await post('folder', { plate: v.plate, name: $('m-folder').value });
      if (res.ok) { v.folder = res.folder || null; if (state.folder && !folders().includes(state.folder)) state.folder = ''; }
      finish(res);
    } else if (m.kind === 'transfer') {
      m.busy = true; renderModal();
      const res = await post('transfer', { plate: v.plate, to: m.pick });
      if (res.ok) { if (res.arrive > 0) { v.status = 'transit'; v.arrive = res.arrive; } else v.status = 'away'; v.at = res.at; }
      finish(res);
    } else if (m.kind === 'keys') {
      m.busy = true; renderModal();
      finish(await post('shareKeys', { plate: v.plate, buyer: m.buyer }));
    } else if (m.kind === 'repair') {
      m.busy = true; renderModal();
      const res = await post('repair', { plate: v.plate });
      if (res.ok) { v.eng = 100; v.body = 100; v.repair = 0; }
      finish(res);
    } else if (m.kind === 'upgrade') {
      m.busy = true; renderModal();
      const res = await post('upgrade');
      if (res.ok) { state.data.garage.slots = res.slots; state.data.upgrade = res.upgrade || null; }
      finish(res);
    } else if (m.kind === 'sell') {
      m.price = $('m-price').value; m.busy = true; renderModal();
      const res = await post('sell', { plate: v.plate, buyer: m.buyer, price: Number(m.price) || 0 });
      if (res.ok) {
        state.data.vehicles = state.data.vehicles.filter((x) => x.plate !== v.plate);
        const first = list()[0];
        state.sel = first ? first.plate : null;
        closeModal(); renderAll();
        if (first) post('preview', { plate: first.plate });
      } else { m.busy = false; renderModal(); }
    }
  });

  // ---- officer impound form ----------------------------------------------------------
  function renderOfficer() {
    const d = state.data;
    $('officerbox').innerHTML = `<div class="row"><div><h2 class="mh hd">${esc(tr('officer_title'))}</h2><div class="msub">${esc(tr('officer_sub'))}</div></div>
        <div class="plate pi-0" style="font-size:18px;padding:6px 12px">${esc(d.plate)}</div></div>
      <div><label class="lb" for="o-reason">${esc(tr('reason'))}</label><textarea id="o-reason" class="fld" rows="3" maxlength="200"></textarea></div>
      <div class="two"><div><label class="lb" for="o-fee">${esc(tr('fee_label'))}</label><input id="o-fee" class="fld" type="number" min="0" value="500"></div>
        <div><label class="lb" for="o-hold">${esc(tr('hold_label'))}</label><input id="o-hold" class="fld" type="number" min="0" value="60"></div></div>
      <div><span class="lb">${esc(tr('who_release'))}</span><div class="two">
        <button type="button" class="btn ${state.ownerRelease ? 'on' : ''}" data-rel="1">${esc(tr('owner_after_hold'))}</button>
        <button type="button" class="btn ${state.ownerRelease ? '' : 'on'}" data-rel="0">${esc(tr('officers_only_btn'))}</button></div></div>
      <div class="btns"><button type="button" class="btn" data-act="cancel">${esc(tr('cancel'))}</button>
        <button type="button" class="btn pri" data-act="confirm">${esc(tr('confirm'))}</button></div>`;
  }

  // ---- events ---------------------------------------------------------------------------
  $('strip').addEventListener('click', (e) => {
    const c = e.target.closest('.vcard');
    if (c) { sfx('select'); select(c.dataset.plate); }
  });

  $('folders').addEventListener('click', (e) => {
    const c = e.target.closest('[data-folder]');
    if (!c) return;
    sfx('select');
    state.folder = c.dataset.folder;
    const items = list();
    if (items.length && !items.some((v) => v.plate === state.sel)) state.sel = items[0].plate;
    renderFolders(); renderStrip(); renderDetail();
    if (state.sel) post('preview', { plate: state.sel });
  });

  $('camera').addEventListener('click', (e) => {
    const c = e.target.closest('[data-cam]');
    if (c) { setCam(c.dataset.cam); return; }
    const o = e.target.closest('[data-popt]');
    if (o) {
      const k = o.dataset.popt;
      state.preview[k] = !state.preview[k];
      sfx('select');
      post('previewOpt', { key: k, value: state.preview[k] });
      renderCamera();
    }
  });

  $('titleblock').addEventListener('click', (e) => {
    const b = e.target.closest('[data-act]');
    if (!b) return;
    if (b.dataset.act === 'access') { sfx('confirm'); post('access'); }
    if (b.dataset.act === 'upgrade') openModal('upgrade');
  });

  async function runPrimary() {
    const v = current();
    if (!v) return;
    const a = primary(v);
    if (a.disabled || !a.act) return;
    sfx('confirm');
    await post(a.act, { plate: v.plate });
  }

  $('detail').addEventListener('click', async (e) => {
    const b = e.target.closest('[data-act]');
    const v = current();
    if (!b || !v || b.disabled) return;
    const act = b.dataset.act;
    if (act === 'fav') {
      v.fav = !v.fav;
      sfx('select');
      renderStrip(); renderDetail();
      post('fav', { plate: v.plate });
    } else if (act === 'takeOut' || act === 'retrieve' || act === 'locate') {
      runPrimary();
    } else if (['transfer', 'rename', 'sell', 'folder', 'history', 'keys', 'repair'].includes(act)) {
      openModal(act);
    }
  });

  $('search').addEventListener('input', (e) => {
    state.q = e.target.value;
    const items = list();
    if (items.length && !items.some((v) => v.plate === state.sel)) state.sel = items[0].plate;
    renderStrip(); renderDetail();
  });

  $('officerbox').addEventListener('click', (e) => {
    const rel = e.target.closest('[data-rel]');
    if (rel) {
      state.ownerRelease = rel.dataset.rel === '1';
      const keep = { r: $('o-reason').value, f: $('o-fee').value, h: $('o-hold').value };
      renderOfficer();
      $('o-reason').value = keep.r; $('o-fee').value = keep.f; $('o-hold').value = keep.h;
      return;
    }
    const b = e.target.closest('[data-act]');
    if (!b) return;
    if (b.dataset.act === 'cancel') post('close');
    if (b.dataset.act === 'confirm') {
      post('impound', {
        reason: $('o-reason').value, fee: Number($('o-fee').value) || 0,
        hold: Number($('o-hold').value) || 0, ownerRelease: state.ownerRelease,
      });
    }
  });

  // ---- keyboard ----------------------------------------------------------------------------
  addEventListener('keydown', (e) => {
    if (app.hidden) return;
    if (e.key === 'Escape') {
      if (state.modal && !state.modal.busy) { closeModal(); return; }
      if (!state.modal) post('close');
      return;
    }
    const typing = /^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement?.tagName || '');
    if (state.view === 'admin') return;
    if (state.modal) {
      if (e.key === 'Enter' && !typing) document.querySelector('#modalbox [data-m="save"]:not(:disabled)')?.click();
      else if (e.key === 'Enter' && document.activeElement?.tagName === 'INPUT') document.querySelector('#modalbox [data-m="save"]:not(:disabled)')?.click();
      return;
    }
    if (state.view === 'officer' || typing) return;
    if (e.key === 'ArrowRight') { step(1); e.preventDefault(); }
    else if (e.key === 'ArrowLeft') { step(-1); e.preventDefault(); }
    else if (e.key === 'Enter') { runPrimary(); e.preventDefault(); }
    else if (/^[1-6]$/.test(e.key)) setCam(CAMS[Number(e.key) - 1]);
    else if (e.key === 'f' || e.key === 'F') document.querySelector('#detail [data-act="fav"]')?.click();
  });

  // ---- gamepad (best effort: works where the NUI browser exposes the Gamepad API) -----------
  const pad = { last: {}, raf: 0 };
  function pollPad() {
    pad.raf = requestAnimationFrame(pollPad);
    if (app.hidden || state.view === 'admin' || state.view === 'officer') return;
    const gp = (navigator.getGamepads ? [...navigator.getGamepads()].find(Boolean) : null);
    if (!gp) return;
    const pressed = (i) => !!gp.buttons[i]?.pressed;
    const edge = (name, i) => { const now = pressed(i), was = pad.last[name]; pad.last[name] = now; return now && !was; };
    const dl = edge('dl', 14), dr = edge('dr', 15), lb = edge('lb', 4), rb = edge('rb', 5), a = edge('a', 0), b = edge('b', 1);
    const cam = (d) => setCam(CAMS[(CAMS.indexOf(state.cam) + d + CAMS.length) % CAMS.length]);
    if (!state.modal) { if (dl) step(-1); if (dr) step(1); if (lb) cam(-1); if (rb) cam(1); }
    if (a) { if (state.modal) document.querySelector('#modalbox [data-m="save"]:not(:disabled)')?.click(); else runPrimary(); }
    if (b) { if (state.modal && !state.modal.busy) closeModal(); else if (!state.modal) post('close'); }
  }
  pollPad();

  // countdowns (impound holds, vehicle deliveries) tick once a second
  setInterval(() => {
    if (app.hidden || !state.data || state.view === 'admin' || state.view === 'officer' || state.modal) return;
    const v = current();
    if (v && (v.status === 'transit' || v.imp)) renderDetail();
  }, 1000);

  // drag the empty scene to rotate the preview vehicle
  let dragX = null;
  $('stage').addEventListener('pointerdown', (e) => { dragX = e.clientX; $('stage').setPointerCapture(e.pointerId); });
  $('stage').addEventListener('pointermove', (e) => {
    if (dragX === null) return;
    const dx = e.clientX - dragX; dragX = e.clientX;
    if (dx) post('rotate', { dx });
  });
  const endDrag = () => { dragX = null; };
  $('stage').addEventListener('pointerup', endDrag);
  $('stage').addEventListener('pointercancel', endDrag);

  const GARAGE_PARTS = ['titleblock', 'tabs', 'themebtn', 'searchbox', 'detail', 'strip', 'hints', 'camera'];

  addEventListener('message', (e) => {
    const m = e.data;
    if (m.action === 'close') { app.hidden = true; closeModal(); return; }
    if (m.action === 'hide') { app.hidden = true; return; }
    if (m.action === 'show') { app.hidden = false; return; }
    if (m.action !== 'open') return;

    state.view = m.view; state.data = m.data; state.t = m.t || {}; state.q = ''; state.folder = ''; state.ownerRelease = true;
    state.sounds = m.sounds !== false; state.t0 = Date.now(); state.cam = 'front';
    state.preview = Object.assign({ spin: true, lights: true }, m.preview || {});
    const cfg = m.theme || {};
    applyTheme(savedMode() || cfg.mode || 'dark', cfg.accent || '#A594FF');
    $('search').value = '';
    closeModal();
    app.hidden = false;

    const isGarage = m.view === 'garage' || m.view === 'impound';
    for (const id of GARAGE_PARTS) $(id).hidden = !isGarage;
    $('folders').hidden = true;
    $('officer').hidden = m.view !== 'officer';
    $('admin').hidden = m.view !== 'admin';
    $('stage').hidden = m.view === 'admin';

    if (m.view === 'admin') { window.ASGAdmin?.open(m.data); return; }
    if (m.view === 'officer') { renderOfficer(); return; }

    const strip = $('strip');
    strip.classList.add('enter');
    setTimeout(() => strip.classList.remove('enter'), 1200);
    const first = list()[0];
    state.sel = first ? first.plate : null;
    renderAll();
    if (first) post('preview', { plate: first.plate });
  });
})();
