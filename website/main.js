/**
 * HERMES COMPANION — MONOCHROME EDITORIAL JAVASCRIPT
 * Handles terminal clipboard copy, diagnostic simulation, and interactive components.
 * Note: Dark mode is handled 100% automatically via CSS (prefers-color-scheme: dark).
 */

(function () {
  'use strict';

  // --- CLIPBOARD COPY ---
  function initClipboard() {
    document.querySelectorAll('.terminal-copy-btn').forEach((btn) => {
      btn.addEventListener('click', () => {
        const targetId = btn.getAttribute('data-copy-target');
        const codeElement = targetId ? document.getElementById(targetId) : btn.closest('.terminal-block').querySelector('pre');
        if (!codeElement) return;

        let text = codeElement.innerText;
        // Clean out prompt characters for seamless terminal paste
        text = text.replace(/^\$\s+/gm, '');

        navigator.clipboard.writeText(text).then(() => {
          const original = btn.textContent;
          btn.textContent = '[ COPIED ]';
          setTimeout(() => {
            btn.textContent = original;
          }, 1800);
        }).catch(() => {
          btn.textContent = '[ ERROR ]';
        });
      });
    });
  }

  // --- FAQ ACCORDION ---
  function initAccordion() {
    document.querySelectorAll('.faq-trigger').forEach((trigger) => {
      trigger.addEventListener('click', () => {
        const item = trigger.closest('.faq-item');
        const isActive = item.classList.contains('active');

        // Close others in same accordion
        const parent = item.closest('.faq-list');
        if (parent) {
          parent.querySelectorAll('.faq-item').forEach((i) => i.classList.remove('active'));
        }

        if (!isActive) {
          item.classList.add('active');
        }
      });
    });
  }

  // --- DIAGNOSTIC TAB SWITCHER ---
  function initDiagnostics() {
    const tabs = document.querySelectorAll('.diag-tab');
    const screens = document.querySelectorAll('.diag-screen');

    tabs.forEach((tab) => {
      tab.addEventListener('click', () => {
        const target = tab.getAttribute('data-diag-target');

        tabs.forEach((t) => t.classList.remove('active'));
        screens.forEach((s) => s.style.display = 'none');

        tab.classList.add('active');
        const activeScreen = document.getElementById(target);
        if (activeScreen) {
          activeScreen.style.display = 'block';
        }
      });
    });
  }

  // --- INITIALIZE ON DOM LOAD ---
  document.addEventListener('DOMContentLoaded', () => {
    initClipboard();
    initAccordion();
    initDiagnostics();
  });
})();
