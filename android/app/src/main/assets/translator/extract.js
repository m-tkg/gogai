(function() {
  // 再実行時(再翻訳)は前回の span を原文のテキストノードに戻してから走査し直す
  if (window.__gogaiSents && window.__gogaiSents.length > 0) {
    const parents = new Set();
    for (const s of window.__gogaiSents) {
      const parent = s.span.parentNode;
      if (!parent) { continue; }
      parent.replaceChild(document.createTextNode(s.src), s.span);
      parents.add(parent);
    }
    parents.forEach(function(p) { p.normalize(); });
  }
  window.__gogaiNodes = [];
  window.__gogaiSents = [];
  // 文(sentence)の表示を更新する。show && 訳あり なら訳文、それ以外は原文。
  // 原文の前後の空白は訳文表示でも保つ(文間の区切り空白を失わないため)。
  function render(s) {
    const showTr = s.show && s.tr !== null;
    let text = s.src;
    if (showTr) {
      const lead = s.src.match(/^\s*/)[0];
      const trail = s.src.match(/\s*$/)[0];
      text = lead + s.tr + trail;
    }
    if (s.span.textContent !== text) { s.span.textContent = text; }
    s.span.classList.toggle('gogai-sent--tr', showTr);
  }
  function ensureStyle() {
    if (document.getElementById('gogai-sent-style')) { return; }
    const style = document.createElement('style');
    style.id = 'gogai-sent-style';
    style.textContent = '.gogai-sent{cursor:pointer}' +
      '.gogai-sent--tr{text-decoration:underline dotted;text-decoration-color:rgba(128,128,128,.55);' +
      'text-decoration-thickness:1px;text-underline-offset:.2em}';
    (document.head || document.documentElement).appendChild(style);
  }
  // pieces[nodeIndex] = そのノードを文単位に分割した文字列配列(連結すると元の nodeValue に一致する)。
  // 各文を span で包み、文書順の通し番号(= 文 index)で window.__gogaiSents に保持する。
  window.__gogaiSplit = function(pieces) {
    const sents = window.__gogaiSents = [];
    ensureStyle();
    for (let i = 0; i < pieces.length; i++) {
      const n = window.__gogaiNodes[i];
      const parts = pieces[i];
      if (!n || !n.parentNode || !parts || parts.length === 0) { continue; }
      const frag = document.createDocumentFragment();
      for (let k = 0; k < parts.length; k++) {
        const span = document.createElement('span');
        span.className = 'gogai-sent';
        span.textContent = parts[k];
        const s = { span: span, src: parts[k], tr: null, show: false };
        span.setAttribute('data-gogai-sent', String(sents.length));
        // タップで原文 ⇄ 訳文を切り替える(訳が届いていない文は通常のクリックとして扱う)
        span.addEventListener('click', function(e) {
          if (s.tr === null) { return; }
          e.preventDefault();
          e.stopPropagation();
          s.show = !s.show;
          render(s);
        }, true);
        sents.push(s);
        frag.appendChild(span);
      }
      n.parentNode.replaceChild(frag, n);
    }
    return sents.length;
  };
  // p = {i: [文index...], t: [訳文...]} 訳文を保持し、表示フラグに従って描画する
  window.__gogaiSetTr = function(p) {
    for (let k = 0; k < p.i.length; k++) {
      const s = window.__gogaiSents[p.i[k]];
      if (s) { s.tr = p.t[k]; render(s); }
    }
  };
  // p = {i: [文index...], s: [bool...]} 訳文を表示するかどうかのフラグを一括設定する
  window.__gogaiSetShow = function(p) {
    for (let k = 0; k < p.i.length; k++) {
      const s = window.__gogaiSents[p.i[k]];
      if (s) { s.show = !!p.s[k]; render(s); }
    }
  };
  // SVG/MATH は span を挿入すると描画されなくなるため対象外(XML 要素は tagName が小文字なので大文字化して比較)
  const reject = ['SCRIPT', 'STYLE', 'NOSCRIPT', 'CODE', 'PRE', 'TEXTAREA', 'SVG', 'MATH'];
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
    acceptNode: function(node) {
      let el = node.parentElement;
      while (el) {
        if (reject.includes(el.tagName.toUpperCase())) { return NodeFilter.FILTER_REJECT; }
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
