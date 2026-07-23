<script setup>
defineProps({
  rows: {
    type: Array,
    default: () => [],
  },
});
</script>

<template>
  <div class="mb-6">
    <h3 class="text-sm font-medium text-n-slate-12 mb-2">
      {{ $t('TEMPLATES_REPORTS.TABLE.TITLE') }}
    </h3>
    <div
      v-if="!rows.length"
      class="text-sm text-n-slate-11 py-4 text-center border border-n-weak rounded-lg"
    >
      {{ $t('TEMPLATES_REPORTS.TABLE.EMPTY') }}
    </div>
    <div v-else class="overflow-x-auto border border-n-weak rounded-lg">
      <table class="min-w-full text-sm">
        <thead class="bg-n-slate-2">
          <tr class="text-left text-n-slate-11">
            <th class="px-3 py-2">
              {{ $t('TEMPLATES_REPORTS.TABLE.TEMPLATE_NAME') }}
            </th>
            <th class="px-3 py-2">{{ $t('TEMPLATES_REPORTS.TABLE.SENT') }}</th>
            <th class="px-3 py-2">
              {{ $t('TEMPLATES_REPORTS.TABLE.DELIVERED') }}
            </th>
            <th class="px-3 py-2">{{ $t('TEMPLATES_REPORTS.TABLE.READ') }}</th>
            <th class="px-3 py-2">
              {{ $t('TEMPLATES_REPORTS.TABLE.FAILED') }}
            </th>
            <th class="px-3 py-2">
              {{ $t('TEMPLATES_REPORTS.TABLE.RESPONDED') }}
            </th>
            <th class="px-3 py-2">
              {{ $t('TEMPLATES_REPORTS.TABLE.RESPONSE_RATE') }}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-n-weak">
          <tr
            v-for="row in rows"
            :key="row.template_name"
            class="text-n-slate-12"
          >
            <td class="px-3 py-2 font-medium">{{ row.template_name }}</td>
            <td class="px-3 py-2">{{ row.sent }}</td>
            <td class="px-3 py-2">{{ row.delivered }}</td>
            <td class="px-3 py-2">{{ row.read }}</td>
            <td class="px-3 py-2">{{ row.failed }}</td>
            <td class="px-3 py-2">{{ row.responded }}</td>
            <td class="px-3 py-2">{{ row.response_rate }}%</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
