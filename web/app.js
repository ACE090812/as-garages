(() => {
  const $ = (id) => document.getElementById(id);
  const app = $('app');
  const state = { view: null, data: null, t: {}, sel: null, q: '', toast: '', ownerRelease: true };
  let toastTimer;

  const post = (name, body) =>
    fetch(`https://${window.GetParentResourceName ? GetParentResourceName() : 'as-garages'}/${name}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}),
    }).then((r) => r.json()).catch(() => ({}));

  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  // tr('slots_of', 3, 10) fills each %s in order
  const tr = (key, ...args) => { let i = 0; return String(state.t[key] ?? key).replace(/%s/g, () => args[i++] ?? ''); };
  const money = (n) => Number(n || 0).toLocaleString('en-US');
  const col = (n) => (n >= 70 ? 'var(--ok)' : n >= 40 ? 'var(--warn)' : 'var(--bad)');
  const STATUS = { in: ['status_in', 'var(--ok)'], out: ['status_out', 'var(--warn)'], imp: ['status_imp', 'var(--bad)'], away: ['status_away', 'var(--muted)'] };

  function fit() {
    const s = Math.min(innerWidth / 1920, innerHeight / 1080);
    app.style.transform = `translate(${(innerWidth - 1920 * s) / 2}px, ${(innerHeight - 1080 * s) / 2}px) scale(${s})`;
  }
  addEventListener('resize', fit);
  fit();

  function dur(sec) {
    sec = Math.max(0, Math.floor(sec));
    const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
    const p = (n) => String(n).padStart(2, '0');
    return h > 0 ? `${h}:${p(m)}:${p(s)}` : `${p(m)}:${p(s)}`;
  }
  function since(epoch) {
    if (!epoch) return tr('never');
    const days = Math.floor((state.data.now - epoch) / 86400);
    return days <= 0 ? tr('today') : days === 1 ? tr('yesterday') : tr('days_ago', days);
  }

  const list = () => {
    const q = state.q.trim().toLowerCase();
    return (state.data?.vehicles || [])
      .filter((v) => !q || v.name.toLowerCase().includes(q) || v.plate.toLowerCase().includes(q))
      .sort((a, b) => Number(b.fav) - Number(a.fav));
  };
  const current = () => (state.data?.vehicles || []).find((v) => v.plate === state.sel);

  function renderTop() {
    const g = state.data.garage;
    const isLot = state.view === 'impound';
    $('titleblock').innerHTML = `<h1 class="hd">${esc(g.label)}</h1><div class="sub"><span>${esc(g.sub || '')}</span>
      <span class="pill">${isLot ? tr('lot_sub', state.data.vehicles.length) : tr('slots_of', g.used, g.slots)}</span></div>`;
    const tabLabel = { mine: 'tab_mine', job: 'tab_job', gang: 'tab_gang', impound: 'tab_impound' }[state.data.tab] || 'tab_mine';
    $('tabs').innerHTML = `<button class="seg on" type="button">${esc(tr(tabLabel))}</button>`;
    $('search').placeholder = tr('search');
    $('hints').innerHTML = `<span><b>Esc</b> ${esc(tr('h_close'))}</span><span><b>${esc(tr('h_rotate'))}</b></span>`;
  }

  function renderStrip() {
    const items = list();
    $('strip').innerHTML = items.length ? items.map((v) => {
      const [k, c] = STATUS[v.status] || STATUS.in;
      return `<button type="button" class="vcard${v.plate === state.sel ? ' sel' : ''}" data-plate="${esc(v.plate)}">
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
      if (v.status === 'away') return { label: tr('stored_at', v.at || '?'), disabled: true };
      return { label: tr('status_imp'), disabled: true };
    }
    const i = v.imp, total = i.fee + i.storage, left = i.until_ - state.data.now;
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
    el.innerHTML = `<div class="row"><div><div class="cls">${esc(v.cls)}</div><h2 class="hd">${esc(v.name)}</h2></div>
        ${lot ? '' : `<button class="btn iconbtn" type="button" data-act="fav" aria-label="${esc(tr('h_fav'))}" style="color:${v.fav ? 'var(--accent)' : 'var(--text)'}">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="${v.fav ? 'currentColor' : 'none'}" stroke="currentColor" stroke-width="2" stroke-linejoin="round" aria-hidden="true"><path d="M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9z"/></svg></button>`}</div>
      <div class="plate">${esc(v.plate)}</div>${body}
      <div class="actions"><button class="btn pri big" type="button" ${a.disabled ? 'disabled' : `data-act="${a.act}"`}>${esc(a.label)}</button>
        ${lot ? '' : `<div class="three"><button class="btn" type="button" disabled title="${esc(tr('soon'))}">${esc(tr('transfer'))}</button>
          <button class="btn" type="button" disabled title="${esc(tr('soon'))}">${esc(tr('rename'))}</button>
          <button class="btn" type="button" disabled title="${esc(tr('soon'))}">${esc(tr('sell'))}</button></div>`}</div>`;
  }

  function renderAll() { renderTop(); renderStrip(); renderDetail(); }

  function select(plate) {
    state.sel = plate;
    renderStrip();
    renderDetail();
    post('preview', { plate });
  }

  function showToast(msg) {
    const el = $('toast');
    el.textContent = msg; el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { el.hidden = true; }, 3500);
  }

  function renderOfficer() {
    const d = state.data;
    $('officerbox').innerHTML = `<div class="row"><div><h2 class="hd">${esc(tr('officer_title'))}</h2><div class="sub">${esc(tr('officer_sub'))}</div></div>
        <div class="plate" style="font-size:18px;padding:6px 12px">${esc(d.plate)}</div></div>
      <div><label for="o-reason">${esc(tr('reason'))}</label><textarea id="o-reason" class="fld" rows="3" maxlength="200"></textarea></div>
      <div class="two"><div><label for="o-fee">${esc(tr('fee_label'))}</label><input id="o-fee" class="fld" type="number" min="0" value="500"></div>
        <div><label for="o-hold">${esc(tr('hold_label'))}</label><input id="o-hold" class="fld" type="number" min="0" value="60"></div></div>
      <div><label>${esc(tr('who_release'))}</label><div class="two">
        <button type="button" class="btn ${state.ownerRelease ? 'on' : ''}" data-rel="1">${esc(tr('owner_after_hold'))}</button>
        <button type="button" class="btn ${state.ownerRelease ? '' : 'on'}" data-rel="0">${esc(tr('officers_only_btn'))}</button></div></div>
      <div class="btns"><button type="button" class="btn" data-act="cancel">${esc(tr('cancel'))}</button>
        <button type="button" class="btn pri" data-act="confirm">${esc(tr('confirm'))}</button></div>`;
  }

  // ---- events -------------------------------------------------------------
  $('strip').addEventListener('click', (e) => {
    const c = e.target.closest('.vcard');
    if (c) select(c.dataset.plate);
  });

  $('detail').addEventListener('click', async (e) => {
    const b = e.target.closest('[data-act]');
    const v = current();
    if (!b || !v) return;
    const act = b.dataset.act;
    if (act === 'fav') {
      v.fav = !v.fav;
      renderStrip(); renderDetail();
      post('fav', { plate: v.plate });
    } else if (act === 'takeOut' || act === 'retrieve' || act === 'locate') {
      await post(act, { plate: v.plate });
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

  addEventListener('keydown', (e) => { if (e.key === 'Escape') post('close'); });

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

  addEventListener('message', (e) => {
    const m = e.data;
    if (m.action === 'close') { app.hidden = true; return; }
    if (m.action !== 'open') return;
    state.view = m.view; state.data = m.data; state.t = m.t || {}; state.q = ''; state.ownerRelease = true;
    $('search').value = '';
    app.hidden = false;

    const isOfficer = m.view === 'officer';
    for (const id of ['titleblock', 'tabs', 'searchbox', 'detail', 'strip', 'hints']) $(id).hidden = isOfficer;
    $('officer').hidden = !isOfficer;
    $('toast').hidden = true;

    if (isOfficer) { renderOfficer(); return; }
    const first = list()[0];
    state.sel = first ? first.plate : null;
    renderAll();
    if (first) post('preview', { plate: first.plate });
  });
})();
