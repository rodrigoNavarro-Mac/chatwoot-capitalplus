<script setup>
defineProps({
  variants: {
    type: Array,
    default: () => [],
  },
});
</script>

<template>
  <div class="mb-6">
    <template v-if="variants.length">
      <h3 class="text-sm font-medium text-n-slate-12 mb-2">
        {{ $t('CADENCE.VARIANTS_TABLE.TITLE') }}
      </h3>
      <p class="text-xs text-n-slate-11 mb-2">
        {{ $t('CADENCE.VARIANTS_TABLE.DESCRIPTION') }}
      </p>
    </template>
    <div
      v-if="variants.length"
      class="overflow-x-auto border border-n-weak rounded-lg"
    >
      <table class="min-w-full text-sm">
        <thead class="bg-n-slate-2">
          <tr class="text-left text-n-slate-11">
            <th class="px-3 py-2">{{ $t('CADENCE.VARIANTS_TABLE.NAME') }}</th>
            <th class="px-3 py-2">
              {{ $t('CADENCE.VARIANTS_TABLE.SEGMENT') }}
            </th>
            <th class="px-3 py-2">
              {{ $t('CADENCE.VARIANTS_TABLE.LEADS_IN_CADENCE') }}
            </th>
            <th class="px-3 py-2">
              {{ $t('CADENCE.VARIANTS_TABLE.RESPONDED') }}
            </th>
            <th class="px-3 py-2">
              {{ $t('CADENCE.VARIANTS_TABLE.RESPONSE_RATE') }}
            </th>
            <th class="px-3 py-2">
              {{ $t('CADENCE.VARIANTS_TABLE.RECOVERED') }}
            </th>
            <th class="px-3 py-2">{{ $t('CADENCE.VARIANTS_TABLE.COLD') }}</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-n-weak">
          <tr
            v-for="variant in variants"
            :key="variant.id"
            class="text-n-slate-12"
          >
            <td class="px-3 py-2">
              {{ variant.name }}
              <span
                v-if="variant.is_default"
                class="ml-1 px-1.5 py-0.5 rounded-full text-xs bg-n-blue-9/10 text-n-blue-11"
              >
                {{ $t('CADENCE.DEFINITIONS.DEFAULT_BADGE') }}
              </span>
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{
                variant.segment_value || $t('CADENCE.DEFINITIONS.NO_SEGMENT')
              }}
            </td>
            <td class="px-3 py-2">{{ variant.leads_in_cadence }}</td>
            <td class="px-3 py-2">{{ variant.responded_count }}</td>
            <td class="px-3 py-2 font-medium">{{ variant.response_rate }}%</td>
            <td class="px-3 py-2">{{ variant.recovered_count }}</td>
            <td class="px-3 py-2">{{ variant.cold_count }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
