// Zoom viewer: click a diagram, image or a table's expand button in the preview (or right-click >
// Open in Viewer) to see it over the page, with zoom, pan, fit-to-window and actual size. Uses
// ldPost from preview.html.
const ldViewer = { el: null, kind: null, source: null, w: 0, h: 0, scale: 1, x: 0, y: 0, drag: null, dragged: false, contextTarget: null };
const LD_VIEWER_STEP = 1.25, LD_VIEWER_PAD = 32, LD_VIEWER_MIN = 0.05, LD_VIEWER_MAX = 40;

// The diagram or image `node` belongs to, if any. Images inside links follow the link on click.
function ldViewerTarget(node, forClick) {
  if (!(node instanceof Element) || node.closest('#ld-viewer')) return null;
  const diagram = node.closest('#content .mermaid');
  if (diagram) return diagram.querySelector('svg') ? diagram : null;
  const img = node.closest('#content img');
  if (img) return !(forClick && img.closest('a')) ? img : null;
  // Tables hold links, checkboxes and text to select, so a click opens them only from their button.
  const expand = node.closest('#content .ld-table-expand');
  if (expand) return expand.parentElement.querySelector('table');
  return forClick ? null : node.closest('#content table');
}

// Puts each table in a wrapper with an expand button, shown on hover. Called by ldRender.
function ldViewerAddTableButtons(container) {
  container.querySelectorAll('table').forEach(table => {
    const wrapper = document.createElement('div');
    wrapper.className = 'ld-table';
    const button = document.createElement('button');
    button.className = 'ld-table-expand';
    button.title = 'Open in Viewer';
    button.textContent = '⤢';
    table.replaceWith(wrapper);
    wrapper.append(button, table);
  });
}

// After a re-render (e.g. a checkbox in the copy was clicked), show the table's new contents.
function ldViewerRefresh() {
  if (!ldViewerIsOpen() || ldViewer.kind !== 'table') return;
  const start = ldViewer.source && ldViewer.source.split('-')[0];
  const table = start && document.querySelector(`#content table[data-sourcepos^="${start}-"]`);
  if (!table) return ldViewerClose();
  ldViewer.el.querySelector('.ld-viewer-item').replaceChildren(ldViewerTableCopy(table));
}

// The copy is laid out again in the viewer (see .ld-viewer-table), rather than keeping the page's
// width, where its columns are squeezed and the text wraps.
function ldViewerTableCopy(table) {
  const copy = table.cloneNode(true);
  copy.classList.add('ld-viewer-table');
  return copy;
}

function ldViewerElement() {
  if (ldViewer.el) return ldViewer.el;
  const v = document.createElement('div');
  v.id = 'ld-viewer';
  v.hidden = true;
  v.innerHTML = `
    <div class="ld-viewer-item"></div>
    <div class="ld-viewer-toolbar">
      <button data-action="zoom-out" title="Zoom Out (−)">−</button>
      <span class="ld-viewer-zoom"></span>
      <button data-action="zoom-in" title="Zoom In (+)">+</button>
      <button data-action="fit" title="Fit to Window (0)">Fit</button>
      <button data-action="reset" title="Actual Size (1)">1:1</button>
      <button data-action="close" title="Close (Esc)">✕</button>
    </div>`;
  document.body.appendChild(v);

  v.addEventListener('click', e => {
    const button = e.target.closest('button[data-action]');
    if (button) {
      ({
        'zoom-in': () => ldViewerZoom(LD_VIEWER_STEP),
        'zoom-out': () => ldViewerZoom(1 / LD_VIEWER_STEP),
        'fit': () => ldViewerFit(),
        'reset': () => ldViewerReset(),
        'close': () => ldViewerClose(),
      })[button.dataset.action]();
    } else if (!ldViewer.dragged && !e.target.closest('.ld-viewer-item, .ld-viewer-toolbar')) {
      ldViewerClose();   // click on the backdrop
    }
  });
  v.addEventListener('dblclick', e => {
    if (e.target.closest('.ld-viewer-item')) ldViewerZoom(2, e.clientX, e.clientY);
  });
  v.addEventListener('pointerdown', e => {
    ldViewer.dragged = false;
    // Pointer capture would turn a click on a checkbox or link in a table into a click on the viewer.
    if (e.button !== 0 || e.target.closest('.ld-viewer-toolbar, input, a')) return;
    ldViewer.drag = { px: e.clientX, py: e.clientY, x: ldViewer.x, y: ldViewer.y };
    try { v.setPointerCapture(e.pointerId); } catch (_) {}
    v.classList.add('ld-dragging');
  });
  v.addEventListener('pointermove', e => {
    const d = ldViewer.drag;
    if (!d) return;
    const dx = e.clientX - d.px, dy = e.clientY - d.py;
    if (Math.abs(dx) + Math.abs(dy) > 3) ldViewer.dragged = true;
    ldViewer.x = d.x + dx; ldViewer.y = d.y + dy;
    ldViewerApply();
  });
  const endDrag = () => { ldViewer.drag = null; v.classList.remove('ld-dragging'); };
  v.addEventListener('pointerup', endDrag);
  v.addEventListener('pointercancel', endDrag);
  // Two-finger scroll pans; ⌘/Ctrl-scroll zooms at the pointer.
  v.addEventListener('wheel', e => {
    e.preventDefault();
    if (e.ctrlKey || e.metaKey) {
      ldViewerZoom(Math.exp(-e.deltaY * 0.01), e.clientX, e.clientY);
    } else {
      ldViewer.x -= e.deltaX; ldViewer.y -= e.deltaY;
      ldViewerApply();
    }
  }, { passive: false });
  return (ldViewer.el = v);
}

function ldViewerOpen(target) {
  const v = ldViewerElement();
  const item = v.querySelector('.ld-viewer-item');
  const rect = target.getBoundingClientRect();
  let content;
  if (target.tagName === 'IMG') {
    ldViewer.kind = 'image';
    ldViewer.w = target.naturalWidth || rect.width || 300;
    ldViewer.h = target.naturalHeight || rect.height || 300;
    content = new Image();
    content.src = target.currentSrc || target.src;
    content.alt = target.alt;
  } else if (target.tagName === 'TABLE') {
    ldViewer.kind = 'table';
    ldViewer.source = target.dataset.sourcepos;
    content = ldViewerTableCopy(target);
    // Measured at its natural size, so the viewer has to be showing.
    item.style.width = item.style.height = '';
    item.replaceChildren(content);
    v.hidden = false;
    ldViewer.w = content.offsetWidth || rect.width || 300;
    ldViewer.h = content.offsetHeight || rect.height || 300;
  } else {
    ldViewer.kind = 'diagram';
    content = target.querySelector('svg').cloneNode(true);
    const box = content.viewBox && content.viewBox.baseVal;
    ldViewer.w = (box && box.width) || rect.width || 300;
    ldViewer.h = (box && box.height) || rect.height || 300;
    content.style.maxWidth = 'none';
  }
  if (ldViewer.kind !== 'table') {
    content.setAttribute('width', ldViewer.w);
    content.setAttribute('height', ldViewer.h);
    item.replaceChildren(content);
  }
  item.style.width = ldViewer.w + 'px';
  item.style.height = ldViewer.h + 'px';
  v.hidden = false;
  document.documentElement.classList.add('ld-viewer-open');
  // Diagrams fill the window; images and tables aren't blown up past their actual size.
  ldViewerFit(ldViewer.kind === 'diagram' ? Infinity : 1);
  ldPost({ type: 'viewer', open: true });
}

function ldViewerClose() {
  const v = ldViewer.el;
  if (!v || v.hidden) return;
  v.hidden = true;
  v.querySelector('.ld-viewer-item').replaceChildren();
  ldViewer.drag = null;
  document.documentElement.classList.remove('ld-viewer-open');
  ldPost({ type: 'viewer', open: false });
}

function ldViewerIsOpen() { return !!ldViewer.el && !ldViewer.el.hidden; }

function ldViewerState() {
  return { open: ldViewerIsOpen(), kind: ldViewerIsOpen() ? ldViewer.kind : null,
           scale: ldViewer.scale, x: ldViewer.x, y: ldViewer.y };
}

function ldViewerApply() {
  const v = ldViewer.el;
  v.querySelector('.ld-viewer-item').style.transform =
    `translate(${ldViewer.x}px, ${ldViewer.y}px) scale(${ldViewer.scale})`;
  v.querySelector('.ld-viewer-zoom').textContent = Math.round(ldViewer.scale * 100) + '%';
}

function ldViewerCenter(scale) {
  ldViewer.scale = scale;
  ldViewer.x = (innerWidth - ldViewer.w * scale) / 2;
  ldViewer.y = (innerHeight - ldViewer.h * scale) / 2;
  ldViewerApply();
}

function ldViewerFit(max = Infinity) {
  const s = Math.min((innerWidth - 2 * LD_VIEWER_PAD) / ldViewer.w, (innerHeight - 2 * LD_VIEWER_PAD) / ldViewer.h, max);
  ldViewerCenter(Math.max(LD_VIEWER_MIN, s));
}

function ldViewerReset() { ldViewerCenter(1); }

// Zooms by `factor`, keeping the point (cx, cy) in place; the window's center by default.
function ldViewerZoom(factor, cx = innerWidth / 2, cy = innerHeight / 2) {
  if (!ldViewerIsOpen()) return;
  const s = Math.min(LD_VIEWER_MAX, Math.max(LD_VIEWER_MIN, ldViewer.scale * factor));
  ldViewer.x = cx - (cx - ldViewer.x) * s / ldViewer.scale;
  ldViewer.y = cy - (cy - ldViewer.y) * s / ldViewer.scale;
  ldViewer.scale = s;
  ldViewerApply();
}

document.addEventListener('click', e => {
  if (ldViewerIsOpen() || e.defaultPrevented) return;
  const target = ldViewerTarget(e.target, true);
  if (!target) return;
  e.preventDefault();
  ldViewerOpen(target);
});

// Remembers what was right-clicked, so the app can offer Open in Viewer in the context menu.
document.addEventListener('contextmenu', e => {
  ldViewer.contextTarget = ldViewerIsOpen() ? null : ldViewerTarget(e.target, false);
  ldPost({ type: 'viewerTarget', available: !!ldViewer.contextTarget });
});

function ldViewerOpenContextTarget() {
  if (ldViewer.contextTarget && ldViewer.contextTarget.isConnected) ldViewerOpen(ldViewer.contextTarget);
}

document.addEventListener('keydown', e => {
  if (!ldViewerIsOpen() || e.metaKey || e.ctrlKey || e.altKey) return;
  const action = {
    'Escape': ldViewerClose,
    '+': () => ldViewerZoom(LD_VIEWER_STEP), '=': () => ldViewerZoom(LD_VIEWER_STEP),
    '-': () => ldViewerZoom(1 / LD_VIEWER_STEP),
    '0': () => ldViewerFit(), '1': ldViewerReset,
  }[e.key];
  if (!action) return;
  e.preventDefault();
  action();
});

// The copy keeps the colors it was opened with, so close it when the theme changes.
matchMedia('(prefers-color-scheme: dark)').addEventListener('change', ldViewerClose);
