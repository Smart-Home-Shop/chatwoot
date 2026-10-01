import { ref } from 'vue';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useUISettings } from 'dashboard/composables/useUISettings';

export const GMAIL_SHORTCUTS_SETTING = 'keyboard_shortcuts_enabled';

// Single source for the bindings and the help overlay. Keys mirror Gmail where Chatwoot has an equivalent.
// `keys` use tinykeys syntax: letters match event.key, space-separated keys are sequences ("g i").
// Symbols are bound as characters (not Shift+…) so they work on layouts where they're unshifted, e.g. AZERTY's !.
// `joiner` tells the overlay how to read `display`: 'or' = alternatives, 'then' = a sequence, unset = pressed together.
export const GMAIL_SHORTCUTS = {
  NEXT: { keys: ['j'], display: ['J'], group: 'NAVIGATION' },
  PREVIOUS: { keys: ['k'], display: ['K'], group: 'NAVIGATION' },
  OPEN: {
    keys: ['o', 'Enter'],
    display: ['O', 'Enter'],
    joiner: 'or',
    group: 'NAVIGATION',
  },
  BACK_TO_LIST: { keys: ['u'], display: ['U'], group: 'NAVIGATION' },
  SEARCH: { keys: ['/'], display: ['/'], group: 'NAVIGATION' },
  GO_TO_CONVERSATIONS: {
    keys: ['g i'],
    display: ['G', 'I'],
    joiner: 'then',
    group: 'NAVIGATION',
  },
  GO_TO_CONTACTS: {
    keys: ['g c'],
    display: ['G', 'C'],
    joiner: 'then',
    group: 'NAVIGATION',
  },
  HELP: { keys: ['?'], display: ['?'], group: 'NAVIGATION' },
  SELECT: { keys: ['x'], display: ['X'], group: 'ACTIONS' },
  RESOLVE: { keys: ['e'], display: ['E'], group: 'ACTIONS' },
  REPLY: { keys: ['r'], display: ['R'], group: 'ACTIONS' },
  LABEL: { keys: [], display: ['L'], group: 'ACTIONS' }, // bound by LabelBox for everyone
  SNOOZE: { keys: ['b'], display: ['B'], group: 'ACTIONS' },
  MARK_UNREAD: { keys: ['Shift+U'], display: ['Shift', 'U'], group: 'ACTIONS' },
  SPAM: { keys: ['!'], display: ['!'], group: 'ACTIONS' },
  UNDO: { keys: ['z'], display: ['Z'], group: 'ACTIONS' },
};

export const GMAIL_SHORTCUT_GROUPS = ['NAVIGATION', 'ACTIONS'];

// Gmail's list cursor: the row j/k highlights when no conversation is open
export const focusedConversationId = ref(null);

// Keys must not fire while the command palette or a modal owns the keyboard
const isOverlayOpen = () =>
  !!document.querySelector('ninja-keys')?.visible ||
  !!document.querySelector('.modal-mask, dialog[open]');

// Ctrl/Cmd/Alt combinations belong to the browser and the existing Alt shortcuts
const hasCommandModifier = e => e.ctrlKey || e.metaKey || e.altKey;

// tinykeys compares letters case-insensitively and allows extra modifiers, so a plain-letter binding like 'u'
// would also fire on Shift+U (mark unread); letters only match without Shift unless the binding asks for it
const isShiftedLetter = (key, e) => /^[a-z]$/.test(key) && e.shiftKey;

// Enter must keep activating focused buttons, links and other controls; the keyboard-cursor row itself is not one
const isEnterOnInteractiveElement = e =>
  e.key === 'Enter' &&
  e.target?.getAttribute?.('aria-current') !== 'true' &&
  !!e.target?.closest?.(
    'a, button, select, summary, [role="button"], [role="switch"], [role="menuitem"], [role="option"]'
  );

/**
 * Registers Gmail-style single-key shortcuts for the mounting component.
 * They only act when the agent has enabled keyboard shortcuts, and never while typing (useKeyboardEvents guards inputs).
 * A handler returns false when it had nothing to do, so the key keeps its native behaviour.
 * @param {Object} actions - map of GMAIL_SHORTCUTS ids to handlers
 * @param {Object} [options] - { allowOverOverlay: ids that may fire while a modal is open, e.g. HELP to close it }
 */
export function useGmailShortcuts(actions, { allowOverOverlay = [] } = {}) {
  const { uiSettings } = useUISettings();

  const events = {};
  Object.entries(actions).forEach(([id, action]) => {
    GMAIL_SHORTCUTS[id].keys.forEach(key => {
      events[key] = e => {
        if (!uiSettings.value?.[GMAIL_SHORTCUTS_SETTING]) return;
        if (hasCommandModifier(e) || isShiftedLetter(key, e)) return;
        if (isEnterOnInteractiveElement(e)) return;
        if (!allowOverOverlay.includes(id) && isOverlayOpen()) return;
        if (action(e) !== false) e.preventDefault();
      };
    });
  });

  useKeyboardEvents(events);
}
