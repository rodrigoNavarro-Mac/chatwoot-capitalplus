<script setup>
defineProps({
  steps: {
    type: Array,
    default: () => [],
  },
});
</script>

<template>
  <div class="mb-6">
    <h3 class="text-sm font-medium text-n-slate-12 mb-2">
      {{ $t('CADENCE.STEPS_TABLE.TITLE') }}
    </h3>
    <div class="overflow-x-auto border border-n-weak rounded-lg">
      <table class="min-w-full text-sm">
        <thead class="bg-n-slate-2">
          <tr class="text-left text-n-slate-11">
            <th class="px-3 py-2">{{ $t('CADENCE.STEPS_TABLE.STEP') }}</th>
            <th class="px-3 py-2">
              {{ $t('CADENCE.STEPS_TABLE.TEMPLATE_KEY') }}
            </th>
            <th class="px-3 py-2">{{ $t('CADENCE.STEPS_TABLE.SENT') }}</th>
            <th class="px-3 py-2">
              {{ $t('CADENCE.STEPS_TABLE.RESPONDED') }}
            </th>
            <th class="px-3 py-2">
              {{ $t('CADENCE.STEPS_TABLE.RESPONSE_RATE') }}
            </th>
            <th class="px-3 py-2">
              {{ $t('CADENCE.STEPS_TABLE.CALL_TASKS_REQUIRED') }}
            </th>
            <th class="px-3 py-2">
              {{ $t('CADENCE.STEPS_TABLE.CALL_TASKS_COMPLETED') }}
            </th>
            <th class="px-3 py-2">
              {{ $t('CADENCE.STEPS_TABLE.CALL_COMPLIANCE_RATE') }}
            </th>
            <th class="px-3 py-2">
              {{ $t('CADENCE.STEPS_TABLE.ADVANCED') }}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-n-weak">
          <tr v-for="step in steps" :key="step.step" class="text-n-slate-12">
            <td class="px-3 py-2">{{ step.step }}</td>
            <td class="px-3 py-2 font-mono text-xs">{{ step.template_key }}</td>
            <td class="px-3 py-2">{{ step.sent }}</td>
            <td class="px-3 py-2">{{ step.responded }}</td>
            <td class="px-3 py-2">{{ step.response_rate }}%</td>
            <td class="px-3 py-2">{{ step.call_tasks_required }}</td>
            <td class="px-3 py-2">{{ step.call_tasks_completed }}</td>
            <td class="px-3 py-2">{{ step.call_compliance_rate }}%</td>
            <td class="px-3 py-2">{{ step.advanced_to_next_step }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
