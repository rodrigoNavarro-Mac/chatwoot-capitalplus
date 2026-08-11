const normalizeForMatch = str =>
  (str || '')
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '');

const escapeRegExp = str => str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

export const templateMatchesInbox = (templateName, inboxName) => {
  const normalizedInboxName = normalizeForMatch(inboxName);
  if (!normalizedInboxName) {
    return false;
  }
  const normalizedTemplateName = normalizeForMatch(templateName);
  return new RegExp(escapeRegExp(normalizedInboxName), 'i').test(
    normalizedTemplateName
  );
};

export { normalizeForMatch };
