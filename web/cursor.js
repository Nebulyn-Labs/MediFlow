(function () {
  // Detect touch devices and skip the custom cursor entirely
  const isTouchDevice = window.matchMedia('(pointer: coarse)').matches;
  if (isTouchDevice) {
    return;
  }

  document.body.classList.add('custom-cursor-active');

  const dot = document.createElement('div');
  dot.className = 'cursor-dot';

  const ring = document.createElement('div');
  ring.className = 'cursor-ring';

  document.body.appendChild(dot);
  document.body.appendChild(ring);

  let mouseX = 0;
  let mouseY = 0;
  let ringX = 0;
  let ringY = 0;

  window.addEventListener('mousemove', function (e) {
    mouseX = e.clientX;
    mouseY = e.clientY;

    // Dot follows instantly
    dot.style.left = mouseX + 'px';
    dot.style.top = mouseY + 'px';
  });

  // Smoothly animate the ring toward the mouse position (lag/trail effect)
  function animateRing() {
    ringX += (mouseX - ringX) * 0.15;
    ringY += (mouseY - ringY) * 0.15;

    ring.style.left = ringX + 'px';
    ring.style.top = ringY + 'px';

    requestAnimationFrame(animateRing);
  }
  requestAnimationFrame(animateRing);

  // Click animation
  window.addEventListener('mousedown', function () {
    dot.classList.add('cursor-click');
    ring.classList.add('cursor-click');
  });

  window.addEventListener('mouseup', function () {
    dot.classList.remove('cursor-click');
    ring.classList.remove('cursor-click');
  });

  // Hover animation for clickable elements
  const hoverSelector = 'a, button, input, textarea, select, label, [role="button"], flt-glass-pane';
  document.addEventListener('mouseover', function (e) {
    if (e.target.closest && e.target.closest(hoverSelector)) {
      dot.classList.add('cursor-hover');
      ring.classList.add('cursor-hover');
    }
  });

  document.addEventListener('mouseout', function (e) {
    if (e.target.closest && e.target.closest(hoverSelector)) {
      dot.classList.remove('cursor-hover');
      ring.classList.remove('cursor-hover');
    }
  });
})();