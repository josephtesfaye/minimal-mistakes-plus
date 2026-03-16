const systemPrefersDark = window.matchMedia('(prefers-color-scheme: dark)');
const savedTheme = localStorage.getItem('theme');

// 1. Function to apply theme
function applyTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);
}

// 2. Initial Load Logic
if (savedTheme) {
    applyTheme(savedTheme); // Respect manual choice
} else {
    applyTheme(systemPrefersDark.matches ? 'dark' : 'light'); // Follow system
}

// 3. Listen for System Changes
systemPrefersDark.addEventListener('change', e => {
    if (!localStorage.getItem('theme')) { // Only change if user hasn't overridden it
        applyTheme(e.matches ? 'dark' : 'light');
    }
});

// 4. Your Manual Toggle Function
function switchTheme() {
    let current = document.documentElement.getAttribute('data-theme');
    let target = current === 'dark' ? 'light' : 'dark';
    applyTheme(target);
    localStorage.setItem('theme', target); // Save preference
}
