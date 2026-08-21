// Advanced (ad-hoc) conversation filters only live in Vuex memory, so a full
// page reload used to silently wipe them and fall back to the default,
// unfiltered conversation list. This persists the last applied filter per
// account/agent so a reload can restore it instead of losing it.
const STORAGE_KEY_PREFIX = 'chatwoot_conversation_filters';

const storageKey = (accountId, userId) =>
  `${STORAGE_KEY_PREFIX}_${accountId}_${userId}`;

export const getPersistedConversationFilters = (accountId, userId) => {
  if (!accountId || !userId) return null;
  try {
    const raw = window.localStorage.getItem(storageKey(accountId, userId));
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) && parsed.length ? parsed : null;
  } catch (error) {
    return null;
  }
};

export const setPersistedConversationFilters = (accountId, userId, filters) => {
  if (!accountId || !userId) return;
  try {
    if (!filters || !filters.length) {
      window.localStorage.removeItem(storageKey(accountId, userId));
      return;
    }
    window.localStorage.setItem(
      storageKey(accountId, userId),
      JSON.stringify(filters)
    );
  } catch (error) {
    // Ignore storage errors (quota exceeded, private browsing, etc.)
  }
};

export const clearPersistedConversationFilters = (accountId, userId) => {
  if (!accountId || !userId) return;
  try {
    window.localStorage.removeItem(storageKey(accountId, userId));
  } catch (error) {
    // Ignore storage errors
  }
};
