import { ref } from 'vue';

const shortcutsMock = vi.hoisted(() => ({ registered: {} }));

vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: vi.fn(events => {
    shortcutsMock.registered = events;
  }),
}));

vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: vi.fn(),
}));

import { useUISettings } from 'dashboard/composables/useUISettings';
import {
  useGmailShortcuts,
  GMAIL_SHORTCUTS_SETTING,
} from 'dashboard/composables/useGmailShortcuts';

const keyEvent = (overrides = {}) => ({
  key: 'j',
  ctrlKey: false,
  metaKey: false,
  altKey: false,
  shiftKey: false,
  target: document.body,
  preventDefault: vi.fn(),
  ...overrides,
});

describe('useGmailShortcuts', () => {
  const uiSettings = ref({ [GMAIL_SHORTCUTS_SETTING]: true });

  beforeEach(() => {
    uiSettings.value = { [GMAIL_SHORTCUTS_SETTING]: true };
    useUISettings.mockReturnValue({ uiSettings });
    shortcutsMock.registered = {};
    document.body.innerHTML = '';
  });

  it('registers every key of each shortcut', () => {
    useGmailShortcuts({ NEXT: vi.fn(), OPEN: vi.fn() });

    expect(Object.keys(shortcutsMock.registered)).toEqual(['j', 'o', 'Enter']);
  });

  it('runs the action and prevents the default when enabled', () => {
    const next = vi.fn();
    useGmailShortcuts({ NEXT: next });
    const event = keyEvent();

    shortcutsMock.registered.j(event);

    expect(next).toHaveBeenCalledWith(event);
    expect(event.preventDefault).toHaveBeenCalled();
  });

  it('does nothing when the agent has not enabled shortcuts', () => {
    uiSettings.value = {};
    const next = vi.fn();
    useGmailShortcuts({ NEXT: next });
    const event = keyEvent();

    shortcutsMock.registered.j(event);

    expect(next).not.toHaveBeenCalled();
    expect(event.preventDefault).not.toHaveBeenCalled();
  });

  it.each(['ctrlKey', 'metaKey', 'altKey'])(
    'ignores the key when %s is held',
    modifier => {
      const next = vi.fn();
      useGmailShortcuts({ NEXT: next });

      shortcutsMock.registered.j(keyEvent({ [modifier]: true }));

      expect(next).not.toHaveBeenCalled();
    }
  );

  it('ignores Shift on plain-letter bindings but not on symbols', () => {
    const back = vi.fn();
    const spam = vi.fn();
    useGmailShortcuts({ BACK_TO_LIST: back, SPAM: spam });

    shortcutsMock.registered.u(keyEvent({ key: 'U', shiftKey: true }));
    shortcutsMock.registered['!'](keyEvent({ key: '!', shiftKey: true }));

    expect(back).not.toHaveBeenCalled();
    expect(spam).toHaveBeenCalled();
  });

  it('keeps Enter for interactive controls but not for the keyboard-cursor row', () => {
    const open = vi.fn();
    useGmailShortcuts({ OPEN: open });
    const button = document.createElement('button');
    const row = document.createElement('div');
    row.setAttribute('aria-current', 'true');

    shortcutsMock.registered.Enter(keyEvent({ key: 'Enter', target: button }));
    expect(open).not.toHaveBeenCalled();

    shortcutsMock.registered.Enter(keyEvent({ key: 'Enter', target: row }));
    expect(open).toHaveBeenCalledTimes(1);
  });

  it.each([
    ['a legacy modal', '<div class="modal-mask"></div>'],
    ['a native dialog', '<dialog open></dialog>'],
    ['an ARIA modal side panel', '<div role="dialog" aria-modal="true"></div>'],
  ])('ignores keys while %s is open', (_, markup) => {
    document.body.innerHTML = markup;
    const next = vi.fn();
    useGmailShortcuts({ NEXT: next });

    shortcutsMock.registered.j(keyEvent());

    expect(next).not.toHaveBeenCalled();
  });

  it('lets allowOverOverlay shortcuts through an open modal', () => {
    document.body.innerHTML = '<div class="modal-mask"></div>';
    const help = vi.fn();
    useGmailShortcuts({ HELP: help }, { allowOverOverlay: ['HELP'] });

    shortcutsMock.registered['?'](keyEvent({ key: '?', shiftKey: true }));

    expect(help).toHaveBeenCalled();
  });

  it('leaves the default behaviour when the action reports it did nothing', () => {
    useGmailShortcuts({ OPEN: () => false });
    const event = keyEvent({ key: 'o' });

    shortcutsMock.registered.o(event);

    expect(event.preventDefault).not.toHaveBeenCalled();
  });
});
