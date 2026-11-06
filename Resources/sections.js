// Collapsible sections in the preview. Each top-level heading gets a disclosure toggle; collapsing
// hides everything up to the next heading of the same or a higher level. The DOM stays flat (scroll
// sync and the viewer rely on it): hidden blocks just get a class. Collapsed headings are kept by
// id, so they stay collapsed when ldRender replaces the content while you type. Uses ldPost from
// preview.html.
const ldCollapsed = new Set();

function ldHeadingLevel(el) {
  const m = /^H([1-6])$/.exec(el.tagName);
  return m ? +m[1] : 0;
}

// Adds the toggles; called by ldRender after the heading ids are set. The toggle is empty (drawn
// by CSS), so the headings' text, and find, are unchanged.
function ldSectionsAddToggles(container) {
  for (const h of container.children) {
    if (!ldHeadingLevel(h)) continue;
    const button = document.createElement('button');
    button.className = 'ld-fold';
    button.tabIndex = -1;
    h.prepend(button);
  }
  ldSectionsApply();
}

// Hides the blocks under collapsed headings, walking the top level with a stack of open headings.
function ldSectionsApply() {
  const stack = [];
  for (const el of document.getElementById('content').children) {
    const level = ldHeadingLevel(el);
    if (level) while (stack.length && stack[stack.length - 1].level >= level) stack.pop();
    el.classList.toggle('ld-folded', stack.some(s => s.collapsed));
    if (level) {
      const collapsed = ldCollapsed.has(el.id);
      el.classList.toggle('ld-collapsed', collapsed);
      const button = el.querySelector(':scope > .ld-fold');
      if (button) button.title = collapsed ? 'Expand section' : 'Collapse section';
      stack.push({ level, collapsed });
    }
  }
  ldAnchors = null; // scroll sync re-measures
  ldPost({ type: 'sections', collapsed: ldCollapsed.size });
}

function ldToggleSection(h) {
  if (!ldCollapsed.delete(h.id)) ldCollapsed.add(h.id);
  ldSectionsApply();
}

function ldCollapseAll() {
  for (const el of document.getElementById('content').children) if (ldHeadingLevel(el)) ldCollapsed.add(el.id);
  ldSectionsApply();
}

function ldExpandAll() {
  ldCollapsed.clear();
  ldSectionsApply();
}

// Opens the sections that hide source line `line` (1-based), e.g. when find selects a match in one.
// A collapsed heading on that very line stays collapsed: it's showing.
function ldRevealLine(line) {
  const stack = [];
  for (const el of document.getElementById('content').children) {
    const level = ldHeadingLevel(el);
    if (!level) continue;
    const start = parseInt(el.dataset.sourcepos, 10);
    if (start > line) break;
    while (stack.length && stack[stack.length - 1].level >= level) stack.pop();
    stack.push({ level, id: el.id, start });
  }
  let changed = false;
  for (const s of stack) if (s.start < line && ldCollapsed.delete(s.id)) changed = true;
  if (changed) ldSectionsApply();
}

document.addEventListener('click', e => {
  const button = e.target.closest('#content .ld-fold');
  if (!button) return;
  e.preventDefault();
  ldToggleSection(button.parentElement);
});
