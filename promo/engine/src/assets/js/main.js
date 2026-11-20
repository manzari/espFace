/**
 * Main JavaScript for App Landing Page
 */

document.addEventListener('DOMContentLoaded', () => {
  initNavbarBurger();
  initNavbarScroll();
  initSmoothScroll();
});

/**
 * Mobile navbar burger menu toggle
 */
function initNavbarBurger() {
  const navbarBurgers = document.querySelectorAll('.navbar-burger');

  navbarBurgers.forEach(burger => {
    burger.addEventListener('click', () => {
      const targetId = burger.dataset.target;
      const target = document.getElementById(targetId);

      burger.classList.toggle('is-active');
      if (target) {
        target.classList.toggle('is-active');
      }
    });
  });
}

/**
 * Navbar scroll effect - adds background on scroll
 */
function initNavbarScroll() {
  const navbar = document.querySelector('.navbar');

  if (!navbar || navbar.classList.contains('is-fixed-top')) {
    return; // Skip for fixed navbar (legal pages)
  }

  window.addEventListener('scroll', () => {
    if (window.scrollY > 50) {
      navbar.classList.add('is-scrolled');
    } else {
      navbar.classList.remove('is-scrolled');
    }
  }, { passive: true });
}

/**
 * Smooth scroll for anchor links
 */
function initSmoothScroll() {
  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', (e) => {
      const href = anchor.getAttribute('href');

      if (href === '#') return;

      const target = document.querySelector(href);
      if (target) {
        e.preventDefault();
        target.scrollIntoView({
          behavior: 'smooth',
          block: 'start'
        });
        closeMobileMenu();
      }
    });
  });

  // Also close the mobile menu when tapping nav links that navigate away
  // (e.g. legal pages → "/#features").
  document.querySelectorAll('.navbar-menu a').forEach(link => {
    link.addEventListener('click', closeMobileMenu);
  });
}

function closeMobileMenu() {
  document.querySelectorAll('.navbar-burger.is-active').forEach(b => b.classList.remove('is-active'));
  document.querySelectorAll('.navbar-menu.is-active').forEach(m => m.classList.remove('is-active'));
}
