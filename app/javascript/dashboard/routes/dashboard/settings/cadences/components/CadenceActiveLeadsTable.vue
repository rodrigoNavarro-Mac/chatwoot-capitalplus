<script setup>
import { useI18n } from 'vue-i18n';
import CadenceStatusBadge from './CadenceStatusBadge.vue';
import EmptyState from 'dashboard/components/widgets/EmptyState.vue';

defineProps({
  leads: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['pause', 'resume', 'cancel']);

const { t } = useI18n();

const formatDate = value => (value ? new Date(value).toLocaleString() : '---');
</script>

<template>
  <div>
    <h3 class="text-sm font-medium text-n-slate-12 mb-2">
      {{ t('CADENCE.ACTIVE_LEADS_TABLE.TITLE') }}
    </h3>
    <div v-if="!leads.length" class="border border-n-weak rounded-lg">
      <EmptyState :title="t('CADENCE.ACTIVE_LEADS_TABLE.EMPTY')" />
    </div>
    <div v-else class="overflow-x-auto border border-n-weak rounded-lg">
      <table class="min-w-full text-sm">
        <thead class="bg-n-slate-2">
          <tr class="text-left text-n-slate-11">
            <th class="px-3 py-2">
              {{ t('CADENCE.ACTIVE_LEADS_TABLE.CONTACT') }}
            </th>
            <th class="px-3 py-2">
              {{ t('CADENCE.ACTIVE_LEADS_TABLE.CONVERSATION') }}
            </th>
            <th class="px-3 py-2">
              {{ t('CADENCE.ACTIVE_LEADS_TABLE.AGENT') }}
            </th>
            <th class="px-3 py-2">
              {{ t('CADENCE.ACTIVE_LEADS_TABLE.CADENCE') }}
            </th>
            <th class="px-3 py-2">
              {{ t('CADENCE.ACTIVE_LEADS_TABLE.STEP') }}
            </th>
            <th class="px-3 py-2">
              {{ t('CADENCE.ACTIVE_LEADS_TABLE.STATUS') }}
            </th>
            <th class="px-3 py-2">
              {{ t('CADENCE.ACTIVE_LEADS_TABLE.NEXT_ACTION') }}
            </th>
            <th class="px-3 py-2">
              {{ t('CADENCE.ACTIVE_LEADS_TABLE.PENDING_CALL') }}
            </th>
            <th class="px-3 py-2">
              {{ t('CADENCE.ACTIVE_LEADS_TABLE.ACTIONS') }}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-n-weak">
          <tr v-for="lead in leads" :key="lead.id" class="text-n-slate-12">
            <td class="px-3 py-2">{{ lead.contact?.name || '---' }}</td>
            <td class="px-3 py-2">
              <router-link
                class="text-n-blue-text hover:underline"
                :to="{
                  name: 'inbox_conversation',
                  params: { conversation_id: lead.conversation.id },
                }"
              >
                #{{ lead.conversation.id }}
              </router-link>
            </td>
            <td class="px-3 py-2">{{ lead.assignee?.name || '---' }}</td>
            <td class="px-3 py-2">
              {{ lead.cadence_definition?.name || '---' }}
              <span
                v-if="lead.cadence_definition?.segment_value"
                class="block text-xs text-n-slate-11"
              >
                {{ lead.cadence_definition.segment_value }}
              </span>
            </td>
            <td class="px-3 py-2">{{ lead.current_step }}</td>
            <td class="px-3 py-2">
              <CadenceStatusBadge :status="lead.status" />
            </td>
            <td class="px-3 py-2">{{ formatDate(lead.next_action_at) }}</td>
            <td class="px-3 py-2">
              {{
                lead.has_pending_call_task
                  ? t('CADENCE.ACTIVE_LEADS_TABLE.YES')
                  : t('CADENCE.ACTIVE_LEADS_TABLE.NO')
              }}
            </td>
            <td class="px-3 py-2 space-x-2 whitespace-nowrap">
              <button
                v-if="
                  ['active', 'waiting_response', 'pending_agent_call'].includes(
                    lead.status
                  )
                "
                class="text-xs text-n-amber-11 hover:underline"
                @click="emit('pause', lead.id)"
              >
                {{ t('CADENCE.ACTIVE_LEADS_TABLE.PAUSE') }}
              </button>
              <button
                v-if="lead.status === 'paused_by_response'"
                class="text-xs text-n-teal-11 hover:underline"
                @click="emit('resume', lead.id)"
              >
                {{ t('CADENCE.ACTIVE_LEADS_TABLE.RESUME') }}
              </button>
              <button
                v-if="!['completed', 'failed', 'cold'].includes(lead.status)"
                class="text-xs text-n-ruby-11 hover:underline"
                @click="emit('cancel', lead.id)"
              >
                {{ t('CADENCE.ACTIVE_LEADS_TABLE.CANCEL') }}
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
