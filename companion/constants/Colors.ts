/** Sentinel Prime — dark theme with teal accents */
const teal = '#14b8a6';
const tealDim = '#0d9488';
const bg = '#141414';
const surface = '#1e1e1e';
const text = '#f5f5f5';
const muted = '#a3a3a3';

export default {
  light: {
    text: '#042f2e',
    background: '#f0fdfa',
    surface: '#ffffff',
    tint: teal,
    tabIconDefault: '#94a3b8',
    tabIconSelected: teal,
    accent: teal,
    warning: '#f59e0b',
    danger: '#ef4444',
  },
  dark: {
    text,
    background: bg,
    surface,
    tint: teal,
    tabIconDefault: muted,
    tabIconSelected: teal,
    accent: teal,
    accentHover: tealDim,
    warning: '#f59e0b',
    danger: '#ef4444',
  },
};
