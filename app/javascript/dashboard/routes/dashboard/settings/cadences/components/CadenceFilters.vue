<script setup>
import { ref, watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import CadencesAPI from 'dashboard/api/cadences';

const filters = defineModel({ type: Object, required: true });

const inboxes = useMapGetter('inboxes/getInboxes');
const agents = useMapGetter('agents/getAgents');
const teams = useMapGetter('teams/getTeams');

const STATUSES = [
  'active',
  'waiting_response',
  'pending_agent_call',
  'paused_by_response',
  'completed',
  'failed',
  'recovered',
  'cold',
];

// Las CadenceDefinition (variantes A/B) son por inbox, así que el selector depende del
// inbox elegido — si se cambia de inbox, la variante seleccionada ya no aplica.
const cadenceDefinitions = ref([]);

const fetchCadenceDefinitions = async inboxId => {
  if (!inboxId) {
    cadenceDefinitions.value = [];
    return;
  }
  try {
    const { data } = await CadencesAPI.getCadenceDefinitions(inboxId);
    cadenceDefinitions.value = data;
  } catch (error) {
    cadenceDefinitions.value = [];
  }
};

watch(
  () => filters.value.inbox_id,
  (inboxId, previousInboxId) => {
    fetchCadenceDefinitions(inboxId);
    if (inboxId !== previousInboxId) {
      filters.value.cadence_definition_id = '';
    }
  },
  { immediate: true }
);
</script>

<template>
  <div class="flex flex-wrap items-end gap-3 mb-4">
    <div class="flex flex-col gap-1">
      <label class="text-xs text-n-slate-11">{{
        $t('CADENCE.FILTERS.INBOX')
      }}</label>
      <select v-model="filters.inbox_id" class="!mb-0 !h-8 text-sm">
        <option value="">{{ $t('CADENCE.FILTERS.ALL') }}</option>
        <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">
          {{ inbox.name }}
        </option>
      </select>
    </div>
    <div class="flex flex-col gap-1">
      <label class="text-xs text-n-slate-11">{{
        $t('CADENCE.FILTERS.CADENCE_DEFINITION')
      }}</label>
      <select
        v-model="filters.cadence_definition_id"
        class="!mb-0 !h-8 text-sm"
        :disabled="!filters.inbox_id"
      >
        <option value="">{{ $t('CADENCE.FILTERS.ALL') }}</option>
        <option
          v-for="definition in cadenceDefinitions"
          :key="definition.id"
          :value="definition.id"
        >
          {{ definition.name
          }}{{
            definition.segment_value ? ` (${definition.segment_value})` : ''
          }}
        </option>
      </select>
    </div>
    <div class="flex flex-col gap-1">
      <label class="text-xs text-n-slate-11">{{
        $t('CADENCE.FILTERS.AGENT')
      }}</label>
      <select v-model="filters.assignee_id" class="!mb-0 !h-8 text-sm">
        <option value="">{{ $t('CADENCE.FILTERS.ALL') }}</option>
        <option v-for="agent in agents" :key="agent.id" :value="agent.id">
          {{ agent.name }}
        </option>
      </select>
    </div>
    <div class="flex flex-col gap-1">
      <label class="text-xs text-n-slate-11">{{
        $t('CADENCE.FILTERS.TEAM')
      }}</label>
      <select v-model="filters.team_id" class="!mb-0 !h-8 text-sm">
        <option value="">{{ $t('CADENCE.FILTERS.ALL') }}</option>
        <option v-for="team in teams" :key="team.id" :value="team.id">
          {{ team.name }}
        </option>
      </select>
    </div>
    <div class="flex flex-col gap-1">
      <label class="text-xs text-n-slate-11">{{
        $t('CADENCE.FILTERS.STATUS')
      }}</label>
      <select v-model="filters.status" class="!mb-0 !h-8 text-sm">
        <option value="">{{ $t('CADENCE.FILTERS.ALL') }}</option>
        <option v-for="status in STATUSES" :key="status" :value="status">
          {{ $t(`CADENCE.STATUS.${status}`) }}
        </option>
      </select>
    </div>
    <div class="flex flex-col gap-1">
      <label class="text-xs text-n-slate-11">{{
        $t('CADENCE.FILTERS.STEP')
      }}</label>
      <input
        v-model.number="filters.step"
        type="number"
        min="1"
        class="!mb-0 !h-8 text-sm"
        :placeholder="$t('CADENCE.FILTERS.ALL')"
      />
    </div>
    <div class="flex flex-col gap-1">
      <label class="text-xs text-n-slate-11">{{
        $t('CADENCE.FILTERS.SINCE')
      }}</label>
      <input v-model="filters.since" type="date" class="!mb-0 !h-8 text-sm" />
    </div>
    <div class="flex flex-col gap-1">
      <label class="text-xs text-n-slate-11">{{
        $t('CADENCE.FILTERS.UNTIL')
      }}</label>
      <input v-model="filters.until" type="date" class="!mb-0 !h-8 text-sm" />
    </div>
  </div>
</template>
