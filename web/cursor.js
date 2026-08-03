(function () {
  const reducedMotionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
  const coarsePointerQuery = window.matchMedia('(pointer: coarse)');

  function shouldDisableCursor() {
    return reducedMotionQuery.matches || coarsePointerQuery.matches;
  }

  let isInitialized = false;
  let dot = null;
  let ring = null;
  let mouseX = 0;
  let mouseY = 0;
  let ringX = 0;
  let ringY = 0;
  let isAnimating = false;
  let animationFrameId = null;
  let hasMoved = false;

  const hoverSelector = 'a, button, input, textarea, select, label, [role="button"], flt-glass-pane';

  function onMouseMove(e) {
    mouseX = e.clientX;
    mouseY = e.clientY;

    if (dot) {
      dot.style.left = mouseX + 'px';
      dot.style.top = mouseY + 'px';
    }

    if (!hasMoved) {
      hasMoved = true;
      ringX = mouseX;
      ringY = mouseY;
      if (ring) {
        ring.style.left = ringX + 'px';
        ring.style.top = ringY + 'px';
      }
    }

    if (!isAnimating) {
      isAnimating = true;
      animationFrameId = requestAnimationFrame(animateRing);
    }
  }

  function animateRing() {
    const dx = mouseX - ringX;
    const dy = mouseY - ringY;

    if (Math.abs(dx) < 0.5 && Math.abs(dy) < 0.5) {
      ringX = mouseX;
      ringY = mouseY;
      if (ring) {
        ring.style.left = ringX + 'px';
        ring.style.top = ringY + 'px';
      }
      isAnimating = false;
      animationFrameId = null;
      return;
    }

    ringX += dx * 0.15;
    ringY += dy * 0.15;

    if (ring) {
      ring.style.left = ringX + 'px';
      ring.style.top = ringY + 'px';
    }

    animationFrameId = requestAnimationFrame(animateRing);
  }

  function onMouseDown() {
    if (dot) dot.classList.add('cursor-click');
    if (ring) ring.classList.add('cursor-click');
  }

  function onMouseUp() {
    if (dot) dot.classList.remove('cursor-click');
    if (ring) ring.classList.remove('cursor-click');
  }

  function onMouseOver(e) {
    if (e.target && e.target.closest && e.target.closest(hoverSelector)) {
      if (dot) dot.classList.add('cursor-hover');
      if (ring) ring.classList.add('cursor-hover');
    }
  }

  function onMouseOut(e) {
    if (e.target && e.target.closest && e.target.closest(hoverSelector)) {
      if (dot) dot.classList.remove('cursor-hover');
      if (ring) ring.classList.remove('cursor-hover');
    }
  }

  function initCursor() {
    if (isInitialized || shouldDisableCursor()) {
      return;
    }

    isInitialized = true;
    hasMoved = false;

    document.body.classList.add('custom-cursor-active');

    dot = document.createElement('div');
    dot.className = 'cursor-dot';

    ring = document.createElement('div');
    ring.className = 'cursor-ring';

    document.body.appendChild(dot);
    document.body.appendChild(ring);

    window.addEventListener('mousemove', onMouseMove);
    window.addEventListener('mousedown', onMouseDown);
    window.addEventListener('mouseup', onMouseUp);
    document.addEventListener('mouseover', onMouseOver);
    document.addEventListener('mouseout', onMouseOut);
  }

  function destroyCursor() {
    if (!isInitialized) {
      return;
    }

    isInitialized = false;

    document.body.classList.remove('custom-cursor-active');

    if (animationFrameId !== null) {
      cancelAnimationFrame(animationFrameId);
      animationFrameId = null;
    }
    isAnimating = false;

    window.removeEventListener('mousemove', onMouseMove);
    window.removeEventListener('mousedown', onMouseDown);
    window.removeEventListener('mouseup', onMouseUp);
    document.removeEventListener('mouseover', onMouseOver);
    document.removeEventListener('mouseout', onMouseOut);

    if (dot) {
      if (dot.remove) dot.remove();
      else if (dot.parentNode) dot.parentNode.removeChild(dot);
    }
    if (ring) {
      if (ring.remove) ring.remove();
      else if (ring.parentNode) ring.parentNode.removeChild(ring);
    }

    dot = null;
    ring = null;
  }

  function updateCursorState() {
    if (shouldDisableCursor()) {
      destroyCursor();
    } else {
      initCursor();
    }
  }

  function listenMediaQuery(mq, callback) {
    if (!mq) return;
    if (mq.addEventListener) {
      mq.addEventListener('change', callback);
    } else if (mq.addListener) {
      mq.addListener(callback);
    }
  }

  listenMediaQuery(reducedMotionQuery, updateCursorState);
  listenMediaQuery(coarsePointerQuery, updateCursorState);

  updateCursorState();
})();