<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useFunctionGetter, useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

import ButtonNext from 'next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import zohoCrmAuthClient from 'dashboard/api/zoho_crm_auth.js';

import Integration from './Integration.vue';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();
const integrationLoaded = ref(false);
const isAuthorizing = ref(false);

const integration = useFunctionGetter(
  'integrations/getIntegration',
  'zoho_crm'
);

const DATACENTERS = ['com', 'eu', 'in', 'com.au', 'jp'];

const clientId = ref('');
const clientSecret = ref('');
const datacenter = ref('com');

const integrationAction = computed(() =>
  integration.value.enabled ? 'disconnect' : ''
);

const authorize = async () => {
  if (!clientId.value || !clientSecret.value || !datacenter.value) {
    useAlert(t('INTEGRATION_SETTINGS.ZOHO_CRM.CONNECTION.FORM.MISSING_FIELDS'));
    return;
  }

  isAuthorizing.value = true;
  try {
    const {
      data: { url },
    } = await zohoCrmAuthClient.generateAuthorization({
      clientId: clientId.value,
      clientSecret: clientSecret.value,
      datacenter: datacenter.value,
    });
    window.location.href = url;
  } catch (error) {
    useAlert(t('INTEGRATION_SETTINGS.ZOHO_CRM.CONNECTION.ERROR'));
    isAuthorizing.value = false;
  }
};

const showRoundTripAlert = () => {
  if (route.query.connected) {
    useAlert(t('INTEGRATION_SETTINGS.ZOHO_CRM.CONNECTION.CONNECTED'));
  } else if (route.query.error) {
    useAlert(t('INTEGRATION_SETTINGS.ZOHO_CRM.CONNECTION.ERROR'));
  }

  if (route.query.connected || route.query.error) {
    router.replace({ query: {} });
  }
};

const initializeZohoCrmIntegration = async () => {
  await store.dispatch('integrations/get', 'zoho_crm');
  integrationLoaded.value = true;
  showRoundTripAlert();
};

onMounted(() => {
  initializeZohoCrmIntegration();
});
</script>

<template>
  <SettingsLayout :is-loading="!integrationLoaded">
    <template #header>
      <BaseSettingsHeader
        :title="$t('INTEGRATION_SETTINGS.ZOHO_CRM.CONNECTION.HEADER')"
        description=""
        :back-button-label="$t('INTEGRATION_SETTINGS.HEADER')"
      />
    </template>
    <template #body>
      <Integration
        :integration-id="integration.id"
        :integration-logo="integration.logo"
        :integration-name="integration.name"
        :integration-description="integration.description"
        :integration-enabled="integration.enabled"
        :integration-action="integrationAction"
        :delete-confirmation-text="{
          title: t('INTEGRATION_SETTINGS.ZOHO_CRM.CONNECTION.DELETE.TITLE'),
          message: t('INTEGRATION_SETTINGS.ZOHO_CRM.CONNECTION.DELETE.MESSAGE'),
        }"
      >
        <template #action>
          <div class="flex flex-col gap-3 w-full max-w-sm">
            <Input
              v-model="clientId"
              :label="
                t('INTEGRATION_SETTINGS.ZOHO_CRM.CONNECTION.FORM.CLIENT_ID')
              "
              size="sm"
            />
            <Input
              v-model="clientSecret"
              type="password"
              :label="
                t('INTEGRATION_SETTINGS.ZOHO_CRM.CONNECTION.FORM.CLIENT_SECRET')
              "
              size="sm"
            />
            <label class="text-sm text-n-slate-11">
              {{
                t('INTEGRATION_SETTINGS.ZOHO_CRM.CONNECTION.FORM.DATA_CENTER')
              }}
              <select
                v-model="datacenter"
                class="reset-base mt-1 block w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-n-slate-12"
              >
                <option v-for="dc in DATACENTERS" :key="dc" :value="dc">
                  {{ dc }}
                </option>
              </select>
            </label>
            <p class="text-xs text-n-slate-10">
              {{ t('INTEGRATION_SETTINGS.ZOHO_CRM.CONNECTION.FORM.HELP_TEXT') }}
            </p>
            <ButtonNext
              faded
              blue
              :label="
                isAuthorizing
                  ? t(
                      'INTEGRATION_SETTINGS.ZOHO_CRM.CONNECTION.FORM.SUBMITTING'
                    )
                  : t('INTEGRATION_SETTINGS.ZOHO_CRM.CONNECTION.FORM.SUBMIT')
              "
              :is-loading="isAuthorizing"
              @click="authorize"
            />
          </div>
        </template>
      </Integration>
    </template>
  </SettingsLayout>
</template>
