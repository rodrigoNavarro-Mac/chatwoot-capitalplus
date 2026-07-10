<script setup>
defineProps({
  templates: {
    type: Array,
    default: () => [],
  },
});
</script>

<template>
  <div class="mb-6">
    <h3 class="text-sm font-medium text-n-slate-12 mb-2">
      {{ $t('CADENCE.TEMPLATES_TABLE.TITLE') }}
    </h3>
    <div class="overflow-x-auto border border-n-weak rounded-lg">
      <table class="min-w-full text-sm">
        <thead class="bg-n-slate-2">
          <tr class="text-left text-n-slate-11">
            <th class="px-3 py-2">
              {{ $t('CADENCE.TEMPLATES_TABLE.TEMPLATE_KEY') }}
            </th>
            <th class="px-3 py-2">
              {{ $t('CADENCE.TEMPLATES_TABLE.TEMPLATE_NAME') }}
            </th>
            <th class="px-3 py-2">{{ $t('CADENCE.TEMPLATES_TABLE.STEP') }}</th>
            <th class="px-3 py-2">{{ $t('CADENCE.TEMPLATES_TABLE.SENT') }}</th>
            <th class="px-3 py-2">
              {{ $t('CADENCE.TEMPLATES_TABLE.RESPONDED') }}
            </th>
            <th class="px-3 py-2">
              {{ $t('CADENCE.TEMPLATES_TABLE.RESPONSE_RATE') }}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-n-weak">
          <tr
            v-for="template in templates"
            :key="template.template_key"
            class="text-n-slate-12"
          >
            <td class="px-3 py-2 font-mono text-xs">
              {{ template.template_key }}
            </td>
            <td class="px-3 py-2">{{ template.template_name || '---' }}</td>
            <td class="px-3 py-2">{{ template.step }}</td>
            <td class="px-3 py-2">{{ template.sent }}</td>
            <td class="px-3 py-2">{{ template.responded }}</td>
            <td class="px-3 py-2">{{ template.response_rate }}%</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
