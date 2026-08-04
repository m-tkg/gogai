(function() {
  window.__gogaiNodes = [];
  window.__gogaiApply = function(i, t) {
    const n = window.__gogaiNodes[i];
    if (n) { n.nodeValue = t; }
  };
  window.__gogaiApplyAll = function(p) {
    for (let k = 0; k < p.i.length; k++) {
      const n = window.__gogaiNodes[p.i[k]];
      if (n) { n.nodeValue = p.t[k]; }
    }
  };
  const reject = ['SCRIPT', 'STYLE', 'NOSCRIPT', 'CODE', 'PRE', 'TEXTAREA'];
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
    acceptNode: function(node) {
      let el = node.parentElement;
      while (el) {
        if (reject.includes(el.tagName)) { return NodeFilter.FILTER_REJECT; }
        el = el.parentElement;
      }
      return node.nodeValue && node.nodeValue.trim().length > 1
        ? NodeFilter.FILTER_ACCEPT
        : NodeFilter.FILTER_SKIP;
    }
  });
  const texts = [];
  let n;
  while ((n = walker.nextNode())) {
    window.__gogaiNodes.push(n);
    texts.push(n.nodeValue);
  }
  return texts;
})();
