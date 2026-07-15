import CadencesAPI from 'dashboard/api/cadences';

// Cache en memoria (por sesión de pestaña) de los pasos de cadencia configurados por
// inbox, para que el composer de plantillas pueda precargar el media_url guardado sin
// refetchear en cada apertura del picker. Un inbox puede tener varias CadenceDefinition
// (una por segmento de razon_compra, más variantes A/B) — se juntan los pasos de todas.
const cache = new Map();

const fetchAllStepsForInbox = async inboxId => {
  try {
    const { data: definitions } =
      await CadencesAPI.getCadenceDefinitions(inboxId);
    const stepLists = await Promise.all(
      definitions.map(definition =>
        CadencesAPI.getStepDefinitions(definition.id).then(({ data }) => data)
      )
    );
    return stepLists.flat();
  } catch (error) {
    return [];
  }
};

export const getCadenceStepDefinitions = inboxId => {
  if (!inboxId) return Promise.resolve([]);

  if (!cache.has(inboxId)) {
    cache.set(inboxId, fetchAllStepsForInbox(inboxId));
  }

  return cache.get(inboxId);
};
