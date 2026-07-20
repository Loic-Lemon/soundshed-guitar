/**
 * Theme Switcher
 * Manages switching between light, dark, and classic themes
 */

export type ThemeName = 'light' | 'dark' | 'classic' | 'light1' | 'dark1';

const THEME_LIST: ThemeName[] = ['light', 'dark', 'classic', 'light1', 'dark1'];
const LEGACY_THEME_MAP: Record<string, ThemeName> = {
  default: 'dark',
  gritty: 'dark',
};

export class ThemeSwitcher {
  private currentTheme: ThemeName = 'dark';
  private body: HTMLElement;

  constructor() {
    this.body = document.body;
    this.setTheme(this.currentTheme, false);
  }

  private normalizeTheme(theme: string): ThemeName {
    if (THEME_LIST.includes(theme as ThemeName)) {
      return theme as ThemeName;
    }
    return LEGACY_THEME_MAP[theme] ?? 'dark';
  }

  /**
   * Set the active theme
   */
  setTheme(theme: ThemeName, persist: boolean = true): void {
    // Remove all theme classes
    this.body.classList.remove('theme-light', 'theme-dark', 'theme-classic', 'theme-light1', 'theme-dark1');
    
    // Add new theme class
    this.body.classList.add(`theme-${theme}`);
    
    this.currentTheme = theme;

    if (persist) {
      // Persist via backend
      import('./bridge.js').then(({ postMessage }) => {
        postMessage({ type: 'setTheme', theme });
      }).catch(() => {});
    }
    
    // Dispatch event for other components to react
    window.dispatchEvent(new CustomEvent('themeChanged', { detail: { theme } }));
  }

  applyTheme(theme: ThemeName): void {
    this.setTheme(theme, false);
  }

  /**
   * Get the current theme
   */
  getCurrentTheme(): ThemeName {
    return this.currentTheme;
  }

  /**
   * Cycle to the next theme
   */
  cycleTheme(): void {
    const currentIndex = THEME_LIST.indexOf(this.currentTheme);
    const nextIndex = (currentIndex + 1) % THEME_LIST.length;
    this.setTheme(THEME_LIST[nextIndex]);
  }

  /**
   * Get theme display name
   */
  getThemeDisplayName(theme?: ThemeName): string {
    const t = theme || this.currentTheme;
    const names: Record<ThemeName, string> = {
      light: 'Light',
      dark: 'Dark',
      classic: 'Vintage',
      light1: 'Light 1',
      dark1: 'Dark 1'
    };
    return names[t];
  }
}

// Export singleton instance
export const themeSwitcher = new ThemeSwitcher();
