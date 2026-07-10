<script setup>
defineProps({
  agents: {
    type: Array,
    default: () => [],
  },
});
</script>

<template>
  <div class="mb-6">
    <h3 class="text-sm font-medium text-n-slate-12 mb-2">
      {{ $t('CADENCE.AGENTS_TABLE.TITLE') }}
    </h3>
    <div class="overflow-x-auto border border-n-weak rounded-lg">
      <table class="min-w-full text-sm">
        <thead class="bg-n-slate-2">
          <tr class="text-left text-n-slate-11">
            <th class="px-3 py-2">{{ $t('CADENCE.AGENTS_TABLE.AGENT') }}</th>
            <th class="px-3 py-2">
              {{ $t('CADENCE.AGENTS_TABLE.LEADS_IN_CADENCE') }}
            </th>
            <th class="px-3 py-2">
              {{ $t('CADENCE.AGENTS_TABLE.RESPONSES') }}
            </th>
            <th class="px-3 py-2">
              {{ $t('CADENCE.AGENTS_TABLE.CALL_TASKS_CREATED') }}
            </th>
            <th class="px-3 py-2">
              {{ $t('CADENCE.AGENTS_TABLE.CALLS_COMPLETED') }}
            </th>
            <th class="px-3 py-2">
              {{ $t('CADENCE.AGENTS_TABLE.CALLS_PENDING') }}
            </th>
            <th class="px-3 py-2">
              {{ $t('CADENCE.AGENTS_TABLE.COMPLIANCE') }}
            </th>
            <th class="px-3 py-2">
              {{ $t('CADENCE.AGENTS_TABLE.RECOVERED') }}
            </th>
            <th class="px-3 py-2">{{ $t('CADENCE.AGENTS_TABLE.COLD') }}</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-n-weak">
          <tr
            v-for="agent in agents"
            :key="agent.user_id"
            class="text-n-slate-12"
          >
            <td class="px-3 py-2">{{ agent.user_name || '---' }}</td>
            <td class="px-3 py-2">{{ agent.leads_in_cadence }}</td>
            <td class="px-3 py-2">{{ agent.responses }}</td>
            <td class="px-3 py-2">{{ agent.call_tasks_created }}</td>
            <td class="px-3 py-2">{{ agent.calls_completed }}</td>
            <td class="px-3 py-2">{{ agent.calls_pending }}</td>
            <td class="px-3 py-2">{{ agent.call_compliance_rate }}%</td>
            <td class="px-3 py-2">{{ agent.recovered_count }}</td>
            <td class="px-3 py-2">{{ agent.cold_count }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
