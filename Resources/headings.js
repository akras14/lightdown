// GitHub-style heading IDs ("Hello, World!" -> "hello-world"; repeats get -1, -2, ...),
// so links like [x](#hello-world) work in the preview and in exported HTML.
function ldAddHeadingIds(root) {
  const used = new Set();
  root.querySelectorAll('h1, h2, h3, h4, h5, h6').forEach(h => {
    const base = h.textContent.trim().toLowerCase()
      .replace(/[^\p{L}\p{M}\p{N}\p{Pc} -]/gu, '')
      .replace(/ /g, '-');
    let id = base, n = 0;
    while (used.has(id)) id = `${base}-${++n}`;
    used.add(id);
    h.id = id;
  });
}
