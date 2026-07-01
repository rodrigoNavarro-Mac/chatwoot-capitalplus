<script setup>
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import { ref, computed } from 'vue';
import { useIntegrationHook } from 'dashboard/composables/useIntegrationHook';
import { useBranding } from 'shared/composables/useBranding';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  integrationId: {
    type: String,
    required: true,
  },
});

defineEmits(['add', 'delete']);

const { integration, hasConnectedHooks } = useIntegrationHook(
  props.integrationId
);

const { replaceInstallationName } = useBranding();

const showSecret = ref(false);
const copied = ref(false);

const webhookSecret = computed(
  () => integration.value.hooks[0]?.settings?.webhook_secret || ''
);

const copySecret = async () => {
  await navigator.clipboard.writeText(webhookSecret.value);
  copied.value = true;
  setTimeout(() => {
    copied.value = false;
  }, 2000);
};
</script>

<template>
  <div
    class="outline outline-n-container outline-1 bg-n-card rounded-xl flex-grow overflow-auto p-4"
  >
    <div class="flex items-center justify-center">
      <div class="flex h-16 w-16 items-center justify-center">
        <img
          :src="`/dashboard/images/integrations/${integrationId}.png`"
          class="max-w-full rounded-md border border-n-weak shadow-sm block dark:hidden bg-n-alpha-3 dark:bg-n-alpha-2"
        />
        <img
          :src="`/dashboard/images/integrations/${integrationId}-dark.png`"
          class="max-w-full rounded-md border border-n-weak shadow-sm hidden dark:block bg-n-alpha-3 dark:bg-n-alpha-2"
        />
      </div>
      <div class="flex flex-col justify-center m-0 mx-4 flex-1">
        <h3 class="mb-1 text-heading-1 text-n-slate-12">
          {{ integration.name }}
        </h3>
        <p class="text-n-slate-11 text-body-main">
          {{ replaceInstallationName(integration.description) }}
        </p>
      </div>
      <div class="flex justify-center items-center mb-0 w-[15%]">
        <div v-if="hasConnectedHooks">
          <div @click="$emit('delete', integration.hooks[0])">
            <Button
              ruby
              faded
              :label="$t('INTEGRATION_APPS.DISCONNECT.BUTTON_TEXT')"
            />
          </div>
        </div>
        <div v-else>
          <Button
            blue
            faded
            :label="$t('INTEGRATION_APPS.CONNECT.BUTTON_TEXT')"
            @click="$emit('add')"
          />
        </div>
      </div>
    </div>

    <!-- Webhook secret (solo si el hook lo tiene configurado) -->
    <div
      v-if="hasConnectedHooks && webhookSecret"
      class="mt-4 border-t border-n-weak pt-4"
    >
      <p class="text-xs font-semibold text-n-slate-11 mb-1.5">Webhook Secret</p>
      <div class="flex items-center gap-2">
        <code
          class="flex-1 rounded-lg border border-n-weak bg-n-alpha-2 px-3 py-1.5 font-mono text-xs text-n-slate-12 break-all select-all"
        >
          {{ showSecret ? webhookSecret : '••••••••••••••••' }}
        </code>
        <button
          class="shrink-0 rounded-lg border border-n-weak px-2 py-1.5 text-xs text-n-slate-9 hover:text-n-slate-12 hover:bg-n-alpha-2 transition-colors"
          :title="showSecret ? 'Ocultar' : 'Mostrar'"
          @click="showSecret = !showSecret"
        >
          <span v-if="showSecret" class="i-lucide-eye-off h-3.5 w-3.5" />
          <span v-else class="i-lucide-eye h-3.5 w-3.5" />
        </button>
        <button
          class="shrink-0 rounded-lg border border-n-weak px-2 py-1.5 text-xs transition-colors"
          :class="
            copied
              ? 'border-n-teal-5 text-n-teal-11 bg-n-teal-2'
              : 'text-n-slate-9 hover:text-n-slate-12 hover:bg-n-alpha-2'
          "
          title="Copiar"
          @click="copySecret"
        >
          <span v-if="copied" class="i-lucide-check h-3.5 w-3.5" />
          <span v-else class="i-lucide-copy h-3.5 w-3.5" />
        </button>
      </div>
      <p class="mt-1 text-[11px] text-n-slate-9">
        Usa este valor en el header
        <code class="rounded bg-n-alpha-3 px-1 font-mono"
          >X-Zoho-Webhook-Secret</code
        >
        al configurar el webhook en Zoho CRM.
      </p>
    </div>
  </div>
</template>
