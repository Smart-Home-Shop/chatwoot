import { ref } from 'vue';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useUISettings } from 'dashboard/composables/useUISettings';

export const GMAIL_SHORTCUTS_SETTING = 'keyboard_shortcuts_enabled';

// Single source for the bindings and the help overlay. Keys mirror Gmail where Chatwoot has an equivalent.
// `keys` use tinykeys syntax: letters match event.key, space-separated keys are sequences ("g i").
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
  HELP: { keys: ['Shift+?'], display: ['?'], group: 'NAVIGATION' },
  SELECT: { keys: ['x'], display: ['X'], group: 'ACTIONS' },
  RESOLVE: { keys: ['e'], display: ['E'], group: 'ACTIONS' },
  REPLY: { keys: ['r'], display: ['R'], group: 'ACTIONS' },
  LABEL: { keys: [], display: ['L'], group: 'ACTIONS' }, // bound by LabelBox for everyone
  SNOOZE: { keys: ['b'], display: ['B'], group: 'ACTIONS' },
  MARK_UNREAD: { keys: ['Shift+U'], display: ['Shift', 'U'], group: 'ACTIONS' },
  SPAM: { keys: ['Shift+!'], display: ['!'], group: 'ACTIONS' },
  UNDO: { keys: ['z'], display: ['Z'], group: 'ACTIONS' },
};

export const GMAIL_SHORTCUT_GROUPS = ['NAVIGATION', 'ACTIONS'];

// Gmail's list cursor: the row j/k highlights when no conversation is open
export const focusedConversationId = ref(null);

// Keys must not fire while the command palette or a modal owns the keyboard
const isOverlayOpen = () =>
  !!document.querySelector('ninja-keys')?.visible ||
  !!document.querySelector('.modal-mask, dialog[open]');

/**
 * Registers Gmail-style single-key shortcuts for the mounting component.
 * They only act when the agent has enabled keyboard shortcuts, and never while typing (useKeyboardEvents guards inputs).
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
        if (!allowOverOverlay.includes(id) && isOverlayOpen()) return;
        e.preventDefault();
        action(e);
      };
    });
  });

  useKeyboardEvents(events);
}
