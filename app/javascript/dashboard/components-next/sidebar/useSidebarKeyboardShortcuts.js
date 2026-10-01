import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useRoute, useRouter } from 'vue-router';
import { useGmailShortcuts } from 'dashboard/composables/useGmailShortcuts';

export function useSidebarKeyboardShortcuts(toggleShortcutModalFn) {
  const route = useRoute();
  const router = useRouter();

  const isCurrentRouteSameAsNavigation = routeName => {
    return route.name === routeName;
  };

  const navigateToRoute = routeName => {
    if (!isCurrentRouteSameAsNavigation(routeName)) {
      router.push({ name: routeName });
    }
  };
  const keyboardEvents = {
    '$mod+Slash': {
      action: () => toggleShortcutModalFn(true),
    },
    '$mod+Escape': {
      action: () => toggleShortcutModalFn(false),
    },
    'Alt+KeyC': {
      action: () => navigateToRoute('home'),
    },
    'Alt+KeyV': {
      action: () => navigateToRoute('contacts_dashboard_index'),
    },
    'Alt+KeyR': {
      action: () => navigateToRoute('account_overview_reports'),
    },
    'Alt+KeyS': {
      action: () => navigateToRoute('agent_list'),
    },
  };

  useGmailShortcuts(
    {
      SEARCH: () => navigateToRoute('search'),
      GO_TO_CONVERSATIONS: () => navigateToRoute('home'),
      GO_TO_CONTACTS: () => navigateToRoute('contacts_dashboard_index'),
      // ? toggles the overlay, so it may fire while that overlay is the open modal
      HELP: () => toggleShortcutModalFn(!document.querySelector('.modal-mask')),
    },
    { allowOverOverlay: ['HELP'] }
  );

  return useKeyboardEvents(keyboardEvents);
}
