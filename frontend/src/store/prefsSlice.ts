/**
 * User-preference slice — translateQuality, dualSubs, etc.
 *
 * These were `useState(() => localStorage.getItem(...))` scattered through
 * App.jsx. Centralising them in the store lets any component read/write
 * without prop-drilling and lets zustand's `persist` middleware handle
 * the storage round-trip once instead of per-field.
 */
import type { StateCreator } from 'zustand';

export type TranslateQuality = 'fast' | 'cinematic';
export type ThemeId = 'gruvbox' | 'gruvbox-light' | 'midnight' | 'nord' | 'solarized' | 'rose-pine' | 'catppuccin';

export interface PrefsSlice {
  translateQuality: TranslateQuality;
  dualSubs: boolean;
  burnSubs: boolean;
  glossaryVisible: boolean;
  /**
   * Phase 4.3 — staged checkpoints. When 'on', between-stage banners nudge
   * the user to review ASR / translation output before advancing. Turn 'off'
   * for rapid-fire workflows where reviewing every stage is overkill.
   */
  reviewMode: 'on' | 'off';

  /**
   * Show RAM/CPU/VRAM live counters in the header. Default OFF — the
   * "Make voices that sound like you" landing screen shouldn't double as a
   * resource monitor. Power users can flip this on via Settings →
   * Performance. The Idle/Ready/Loading status badge + Flush button stay
   * visible regardless because they're action-relevant.
   */
  showHeaderLiveStats: boolean;

  setTranslateQuality: (q: TranslateQuality) => void;
  setDualSubs: (on: boolean) => void;
  setBurnSubs: (on: boolean) => void;
  setGlossaryVisible: (on: boolean) => void;
  setReviewMode: (mode: 'on' | 'off') => void;
  setShowHeaderLiveStats: (on: boolean) => void;

  theme: ThemeId;
  setTheme: (id: ThemeId) => void;
}

export const createPrefsSlice: StateCreator<PrefsSlice, [], [], PrefsSlice> = (set) => ({
  translateQuality: 'fast',
  dualSubs: false,
  burnSubs: false,
  glossaryVisible: true,
  reviewMode: 'on',
  showHeaderLiveStats: false,

  setTranslateQuality:    (q) => set({ translateQuality: q }),
  setDualSubs:            (on) => set({ dualSubs: on }),
  setBurnSubs:            (on) => set({ burnSubs: on }),
  setGlossaryVisible:     (on) => set({ glossaryVisible: on }),
  setReviewMode:          (mode) => set({ reviewMode: mode }),
  setShowHeaderLiveStats: (on) => set({ showHeaderLiveStats: on }),

  theme: 'gruvbox',
  setTheme: (id) => {
    set({ theme: id });
    // Remove the FOUC-prevention inline style tag injected by index.html
    // so it doesn't fight the cascade when switching themes at runtime.
    const fouc = document.getElementById('fouc-theme');
    if (fouc) fouc.remove();

    // Apply to DOM — gruvbox is default (no attribute)
    if (id === 'gruvbox') {
      document.documentElement.removeAttribute('data-theme');
      document.documentElement.style.background = '';
    } else {
      document.documentElement.setAttribute('data-theme', id);
    }
    // Set color-scheme so native scrollbars/form controls match
    document.documentElement.style.colorScheme = id === 'gruvbox-light' ? 'light' : 'dark';
    // Update html background for light theme
    if (id === 'gruvbox-light') {
      document.documentElement.style.background = '#ebdbb2';
    } else {
      document.documentElement.style.background = '#1d2021';
    }
  },
});
