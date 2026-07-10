<script setup>
import { useMapGetter } from 'dashboard/composables/store';

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

const STEPS = [1, 2, 3, 4, 5, 6];
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
      <select v-model="filters.step" class="!mb-0 !h-8 text-sm">
        <option value="">{{ $t('CADENCE.FILTERS.ALL') }}</option>
        <option v-for="step in STEPS" :key="step" :value="step">
          {{ step }}
        </option>
      </select>
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
