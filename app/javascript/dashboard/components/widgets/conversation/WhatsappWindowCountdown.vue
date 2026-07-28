<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useCountdown } from 'dashboard/composables/useCountdown';

const props = defineProps({
  expiresAt: { type: Number, default: null },
});

const { t } = useI18n();
const { formatted } = useCountdown(computed(() => props.expiresAt));
</script>

<template>
  <span
    v-if="formatted"
    class="text-xs text-n-amber-11 whitespace-nowrap"
    :title="t('CONVERSATION.WHATSAPP_WINDOW_COUNTDOWN_TOOLTIP')"
  >
    {{ t('CONVERSATION.WHATSAPP_WINDOW_COUNTDOWN', { time: formatted }) }}
  </span>
</template>
