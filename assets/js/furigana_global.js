function frgntrToggleGlobalHover(el) {
    const isHidden = el.classList.contains('fa-eye-slash');
    if (isHidden) {
        el.classList.replace('fa-eye-slash', 'fa-eye');
        document.querySelectorAll('rt:not(.has-local-hover)').forEach(rt => rt.classList.remove('frgntr_hidden'));
    } else {
        el.classList.replace('fa-eye', 'fa-eye-slash');
        document.querySelectorAll('rt:not(.has-local-hover)').forEach(rt => rt.classList.add('frgntr_hidden'));
    }
}

function frgntrToggleGlobalSelectable(el) {
    const isSelectable = el.classList.contains('fa-unlock');
    if (isSelectable) {
        el.classList.replace('fa-unlock', 'fa-lock');
        document.querySelectorAll('rt:not(.has-local-selectable)').forEach(rt => rt.classList.add('frgntr_unselectable'));
    } else {
        el.classList.replace('fa-lock', 'fa-unlock');
        document.querySelectorAll('rt:not(.has-local-selectable)').forEach(rt => rt.classList.remove('frgntr_unselectable'));
    }
}

function frgntrToggleLocalHover(el) {
    const isHidden = el.classList.contains('fa-eye-slash');
    const rts = el.parentElement.parentElement.querySelectorAll('rt');
    if (isHidden) {
        el.classList.replace('fa-eye-slash', 'fa-eye');
        rts.forEach(rt => rt.classList.remove('frgntr_hidden'));
    } else {
        el.classList.replace('fa-eye', 'fa-eye-slash');
        rts.forEach(rt => rt.classList.add('frgntr_hidden'));
    }
}

function frgntrToggleLocalSelectable(el) {
    const isSelectable = el.classList.contains('fa-unlock');
    const rts = el.parentElement.parentElement.querySelectorAll('rt');
    if (isSelectable) {
        el.classList.replace('fa-unlock', 'fa-lock');
        rts.forEach(rt => rt.classList.add('frgntr_unselectable'));
    } else {
        el.classList.replace('fa-lock', 'fa-unlock');
        rts.forEach(rt => rt.classList.remove('frgntr_unselectable'));
    }
}

function frgntrToggleDropdown(el) {
    document.getElementById('frgntr-mode-menu').classList.toggle('show');
}

function frgntrSelectMode(el) {
    const mode = el.getAttribute('data-mode');
    const iconClass = el.getAttribute('data-icon');
    document.querySelectorAll('.frgntr-dropdown-item').forEach(item => item.classList.remove('active'));
    el.classList.add('active');
    document.getElementById('frgntr-mode-btn').className = `fas ${iconClass} frgntr-icon`;
    window.frgntrLiveMode = mode;
    document.getElementById('frgntr-mode-menu').classList.remove('show');
    const liveInput = document.querySelector('.frgntr-live-input');
    if (liveInput && liveInput.value) {
        liveInput.dispatchEvent(new Event('input'));
    }
}

function frgntrToggleTransDropdown(el) {
    document.getElementById('frgntr-trans-menu').classList.toggle('show');
}

function frgntrSelectTranslation(el) {
    const target = el.getAttribute('data-target');
    const iconClass = el.getAttribute('data-icon');
    document.querySelectorAll('#frgntr-trans-menu .frgntr-dropdown-item').forEach(item => item.classList.remove('active'));
    el.classList.add('active');
    const btn = document.getElementById('frgntr-trans-btn');
    btn.className = `fas ${iconClass} frgntr-icon`;
    window.frgntrLiveTransTarget = target;
    document.getElementById('frgntr-trans-menu').classList.remove('show');
    const liveInput = document.querySelector('.frgntr-live-input');
    if (liveInput && liveInput.value) liveInput.dispatchEvent(new Event('input'));
}

window.addEventListener('click', function(e) {
    if (!e.target.matches('#frgntr-mode-btn')) {
        const menu = document.getElementById('frgntr-mode-menu');
        if (menu && menu.classList.contains('show')) menu.classList.remove('show');
    }
    if (!e.target.matches('#frgntr-trans-btn')) {
        const menu = document.getElementById('frgntr-trans-menu');
        if (menu && menu.classList.contains('show')) menu.classList.remove('show');
    }
});
