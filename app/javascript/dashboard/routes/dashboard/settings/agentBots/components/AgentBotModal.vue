<script setup>
import { ref, computed, reactive, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { required, helpers, url, requiredIf } from '@vuelidate/validators';
import { useVuelidate } from '@vuelidate/core';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { useToggle } from '@vueuse/core';

const props = defineProps({
  type: {
    type: String,
    default: 'create',
    validator: value => ['create', 'edit'].includes(value),
  },
  selectedBot: {
    type: Object,
    default: () => ({}),
  },
});

const BOT_TYPES = {
  WEBHOOK: 'webhook',
  INTERNAL_FLOW: 'internal_flow',
};

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import AccessToken from 'dashboard/routes/dashboard/settings/profile/AccessToken.vue';
import FlowBuilderModal from './FlowBuilderModal.vue';

const MODAL_TYPES = {
  CREATE: 'create',
  EDIT: 'edit',
};

const store = useStore();
const { t } = useI18n();
const dialogRef = ref(null);
const flowBuilderRef = ref(null);
const uiFlags = useMapGetter('agentBots/getUIFlags');

const formState = reactive({
  botName: '',
  botDescription: '',
  botType: BOT_TYPES.WEBHOOK,
  botUrl: '',
  botConfig: '',
  botAvatar: null,
  botAvatarUrl: '',
});

const [showAccessToken, toggleAccessToken] = useToggle();
const accessToken = ref('');
const botSecret = ref('');

const isWebhookBot = computed(() => formState.botType === BOT_TYPES.WEBHOOK);
const isInternalFlowBot = computed(
  () => formState.botType === BOT_TYPES.INTERNAL_FLOW
);

const flowSummary = computed(() => {
  if (!formState.botConfig) return null;
  try {
    const c = JSON.parse(formState.botConfig);
    return {
      steps: Object.keys(c.steps || {}).length,
      variables: Object.keys(c.variables || {}).length,
      initialStep: c.initial_step || '',
    };
  } catch {
    return null;
  }
});

const validJSONConfig = value => {
  if (!value) return true;
  try {
    JSON.parse(value);
    return true;
  } catch {
    return false;
  }
};

const validationRules = computed(() => ({
  botName: {
    required: helpers.withMessage(
      () => t('AGENT_BOTS.FORM.ERRORS.NAME'),
      required
    ),
  },
  botUrl: {
    requiredIf: helpers.withMessage(
      () => t('AGENT_BOTS.FORM.ERRORS.URL'),
      requiredIf(isWebhookBot)
    ),
    url: helpers.withMessage(() => t('AGENT_BOTS.FORM.ERRORS.VALID_URL'), url),
  },
  botConfig: {
    requiredIf: helpers.withMessage(
      () => t('AGENT_BOTS.FORM.ERRORS.BOT_CONFIG'),
      requiredIf(isInternalFlowBot)
    ),
    validJSON: helpers.withMessage(
      () => t('AGENT_BOTS.FORM.ERRORS.INVALID_JSON'),
      validJSONConfig
    ),
  },
}));

const v$ = useVuelidate(validationRules, formState);

const isLoading = computed(() =>
  props.type === MODAL_TYPES.CREATE
    ? uiFlags.value.isCreating
    : uiFlags.value.isUpdating
);

const dialogTitle = computed(() => {
  if (showAccessToken.value) {
    return t('AGENT_BOTS.ACCESS_TOKEN.TITLE');
  }

  return props.type === MODAL_TYPES.CREATE
    ? t('AGENT_BOTS.ADD.TITLE')
    : t('AGENT_BOTS.EDIT.TITLE');
});

const dialogDescription = computed(() => {
  if (showAccessToken.value) {
    return t('AGENT_BOTS.ACCESS_TOKEN.DESCRIPTION');
  }
  return '';
});

const confirmButtonLabel = computed(() =>
  props.type === MODAL_TYPES.CREATE
    ? t('AGENT_BOTS.FORM.CREATE')
    : t('AGENT_BOTS.FORM.UPDATE')
);

const botNameError = computed(() =>
  v$.value.botName.$error ? v$.value.botName.$errors[0]?.$message : ''
);

const botUrlError = computed(() =>
  v$.value.botUrl.$error ? v$.value.botUrl.$errors[0]?.$message : ''
);

const botConfigError = computed(() =>
  v$.value.botConfig.$error ? v$.value.botConfig.$errors[0]?.$message : ''
);

const showAccessTokenInput = computed(
  () =>
    showAccessToken.value ||
    props.type === MODAL_TYPES.EDIT ||
    accessToken.value
);

const resetForm = () => {
  Object.assign(formState, {
    botName: '',
    botDescription: '',
    botType: BOT_TYPES.WEBHOOK,
    botUrl: '',
    botConfig: '',
    botAvatar: null,
    botAvatarUrl: '',
  });
  v$.value.$reset();
};

const handleImageUpload = ({ file, url: avatarUrl }) => {
  formState.botAvatar = file;
  formState.botAvatarUrl = avatarUrl;
};

const handleAvatarDelete = async () => {
  if (props.selectedBot?.id) {
    try {
      await store.dispatch(
        'agentBots/deleteAgentBotAvatar',
        props.selectedBot.id
      );
      formState.botAvatar = null;
      formState.botAvatarUrl = '';
      useAlert(t('AGENT_BOTS.AVATAR.SUCCESS_DELETE'));
    } catch (error) {
      useAlert(t('AGENT_BOTS.AVATAR.ERROR_DELETE'));
    }
  } else {
    formState.botAvatar = null;
    formState.botAvatarUrl = '';
  }
};

const handleSubmit = async () => {
  v$.value.$touch();
  if (v$.value.$invalid) return;
  if (showAccessToken.value) return;

  const botData = {
    name: formState.botName,
    description: formState.botDescription,
    bot_type: formState.botType,
    avatar: formState.botAvatar,
    ...(formState.botType === BOT_TYPES.WEBHOOK
      ? { outgoing_url: formState.botUrl }
      : { bot_config: formState.botConfig }),
  };

  const isCreate = props.type === MODAL_TYPES.CREATE;

  try {
    const actionPayload = isCreate
      ? botData
      : { id: props.selectedBot.id, data: botData };

    const response = await store.dispatch(
      `agentBots/${isCreate ? 'create' : 'update'}`,
      actionPayload
    );

    const alertKey = isCreate
      ? t('AGENT_BOTS.ADD.API.SUCCESS_MESSAGE')
      : t('AGENT_BOTS.EDIT.API.SUCCESS_MESSAGE');
    useAlert(alertKey);

    // Show access token and secret after creation
    if (isCreate) {
      const {
        access_token: responseAccessToken,
        secret: responseSecret,
        id,
      } = response || {};

      if (id && responseAccessToken) {
        accessToken.value = responseAccessToken;
        botSecret.value = responseSecret || '';
        toggleAccessToken(true);
      } else {
        accessToken.value = '';
        botSecret.value = '';
        dialogRef.value.close();
      }
    } else {
      dialogRef.value.close();
    }

    resetForm();
  } catch (error) {
    const errorKey = isCreate
      ? t('AGENT_BOTS.ADD.API.ERROR_MESSAGE')
      : t('AGENT_BOTS.EDIT.API.ERROR_MESSAGE');
    useAlert(errorKey);
  }
};

const initializeForm = () => {
  if (props.selectedBot && Object.keys(props.selectedBot).length) {
    const {
      name,
      description,
      outgoing_url: botUrl,
      bot_type: botType,
      thumbnail,
      bot_config: botConfig,
      access_token: botAccessToken,
      secret: botSecretValue,
    } = props.selectedBot;
    formState.botName = name || '';
    formState.botDescription = description || '';
    formState.botType = botType || BOT_TYPES.WEBHOOK;
    formState.botUrl = botUrl || '';
    formState.botConfig =
      botConfig && Object.keys(botConfig).length
        ? JSON.stringify(botConfig, null, 2)
        : '';
    formState.botAvatarUrl = thumbnail || '';

    if (props.type === MODAL_TYPES.EDIT) {
      if (botAccessToken) accessToken.value = botAccessToken;
      if (botSecretValue) botSecret.value = botSecretValue;
    }
  } else {
    resetForm();
  }
};

const onCopyToken = async value => {
  await copyTextToClipboard(value);
  useAlert(t('AGENT_BOTS.ACCESS_TOKEN.COPY_SUCCESSFUL'));
};

const onCopySecret = async value => {
  await copyTextToClipboard(value || botSecret.value);
  useAlert(t('AGENT_BOTS.SECRET.COPY_SUCCESS'));
};

const onResetSecret = async () => {
  const response = await store.dispatch(
    'agentBots/resetSecret',
    props.selectedBot.id
  );
  if (response) {
    botSecret.value = response.secret;
    useAlert(t('AGENT_BOTS.SECRET.RESET_SUCCESS'));
  } else {
    useAlert(t('AGENT_BOTS.SECRET.RESET_ERROR'));
  }
};

const onResetToken = async () => {
  const response = await store.dispatch(
    'agentBots/resetAccessToken',
    props.selectedBot.id
  );
  if (response) {
    accessToken.value = response.access_token;
    useAlert(t('AGENT_BOTS.ACCESS_TOKEN.RESET_SUCCESS'));
  } else {
    useAlert(t('AGENT_BOTS.ACCESS_TOKEN.RESET_ERROR'));
  }
};

const closeModal = () => {
  if (!showAccessToken.value) v$.value?.$reset();
  accessToken.value = '';
  botSecret.value = '';
  toggleAccessToken(false);
};

const onClickClose = () => {
  closeModal();
  dialogRef.value.close();
};

watch(() => props.selectedBot, initializeForm, { immediate: true, deep: true });

defineExpose({ dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    :title="dialogTitle"
    :description="dialogDescription"
    :show-cancel-button="false"
    :show-confirm-button="false"
    @close="closeModal"
  >
    <form class="flex flex-col gap-4" @submit.prevent="handleSubmit">
      <div
        v-if="!showAccessToken || type === MODAL_TYPES.EDIT"
        class="flex flex-col gap-4"
      >
        <div class="mb-2 flex flex-col items-start">
          <span class="mb-2 text-sm font-medium text-n-slate-12">
            {{ $t('AGENT_BOTS.FORM.AVATAR.LABEL') }}
          </span>
          <Avatar
            :src="formState.botAvatarUrl"
            :name="formState.botName"
            :size="68"
            allow-upload
            icon-name="i-lucide-bot-message-square"
            @upload="handleImageUpload"
            @delete="handleAvatarDelete"
          />
        </div>

        <Input
          id="bot-name"
          v-model="formState.botName"
          :label="$t('AGENT_BOTS.FORM.NAME.LABEL')"
          :placeholder="$t('AGENT_BOTS.FORM.NAME.PLACEHOLDER')"
          :message="botNameError"
          :message-type="botNameError ? 'error' : 'info'"
          @blur="v$.botName.$touch()"
        />

        <TextArea
          id="bot-description"
          v-model="formState.botDescription"
          :label="$t('AGENT_BOTS.FORM.DESCRIPTION.LABEL')"
          :placeholder="$t('AGENT_BOTS.FORM.DESCRIPTION.PLACEHOLDER')"
        />

        <div class="flex flex-col gap-2">
          <label class="text-sm font-medium text-n-slate-12">
            {{ $t('AGENT_BOTS.FORM.BOT_TYPE.LABEL') }}
          </label>
          <div class="flex gap-2">
            <NextButton
              :variant="formState.botType === 'webhook' ? 'solid' : 'outline'"
              :label="$t('AGENT_BOTS.FORM.BOT_TYPE.WEBHOOK')"
              size="sm"
              type="button"
              :disabled="type === MODAL_TYPES.EDIT"
              @click="formState.botType = 'webhook'"
            />
            <NextButton
              :variant="
                formState.botType === 'internal_flow' ? 'solid' : 'outline'
              "
              :label="$t('AGENT_BOTS.FORM.BOT_TYPE.INTERNAL_FLOW')"
              size="sm"
              type="button"
              :disabled="type === MODAL_TYPES.EDIT"
              @click="formState.botType = 'internal_flow'"
            />
          </div>
          <p class="text-xs text-n-slate-11">
            {{
              formState.botType === 'internal_flow'
                ? $t('AGENT_BOTS.INTERNAL_FLOW.DESCRIPTION')
                : $t('AGENT_BOTS.WEBHOOK.DESCRIPTION')
            }}
          </p>
        </div>

        <Input
          v-if="formState.botType === 'webhook'"
          id="bot-url"
          v-model="formState.botUrl"
          :label="$t('AGENT_BOTS.FORM.WEBHOOK_URL.LABEL')"
          :placeholder="$t('AGENT_BOTS.FORM.WEBHOOK_URL.PLACEHOLDER')"
          :message="botUrlError"
          :message-type="botUrlError ? 'error' : 'info'"
          @blur="v$.botUrl.$touch()"
        />

        <div
          v-if="formState.botType === 'internal_flow'"
          class="flex flex-col gap-3"
        >
          <!-- Summary card (when flow is configured) -->
          <div
            v-if="flowSummary"
            class="flex items-start justify-between rounded-xl border border-n-blue-6 bg-n-blue-3 px-4 py-3"
          >
            <div class="flex flex-col gap-0.5">
              <p class="text-sm font-semibold text-n-blue-12">
                {{ $t('AGENT_BOTS.FLOW_BUILDER.SUMMARY.CONFIGURED') }}
              </p>
              <p class="text-xs text-n-blue-11">
                <span class="font-medium">{{
                  $t('AGENT_BOTS.FLOW_BUILDER.SUMMARY.STEPS', {
                    n: flowSummary.steps,
                  })
                }}</span>
                ·
                <span class="font-medium">{{
                  $t('AGENT_BOTS.FLOW_BUILDER.SUMMARY.VARIABLES', {
                    n: flowSummary.variables,
                  })
                }}</span>
                · {{ $t('AGENT_BOTS.FLOW_BUILDER.SUMMARY.INITIAL') }}:
                <code class="font-mono">{{
                  flowSummary.initialStep || '—'
                }}</code>
              </p>
            </div>
            <span
              class="i-lucide-check-circle-2 mt-0.5 h-5 w-5 shrink-0 text-n-blue-10"
            />
          </div>

          <!-- Empty state -->
          <div
            v-else
            class="flex items-center gap-3 rounded-xl border border-dashed border-n-weak bg-n-alpha-1 px-4 py-3"
          >
            <span class="i-lucide-git-branch h-5 w-5 shrink-0 text-n-slate-8" />
            <p class="text-sm text-n-slate-9">
              {{
                $t('AGENT_BOTS.FLOW_BUILDER.EMPTY_STATE', {
                  button: $t('AGENT_BOTS.FLOW_BUILDER.CONFIGURE_BUTTON'),
                })
              }}
            </p>
          </div>

          <NextButton
            variant="outline"
            icon="i-lucide-git-branch"
            :label="
              flowSummary
                ? $t('AGENT_BOTS.FLOW_BUILDER.EDIT_BUTTON')
                : $t('AGENT_BOTS.FLOW_BUILDER.CONFIGURE_BUTTON')
            "
            type="button"
            @click="flowBuilderRef.dialogRef.open()"
          />

          <p v-if="botConfigError" class="text-xs text-n-ruby-10">
            {{ botConfigError }}
          </p>
        </div>
      </div>

      <div
        v-if="botSecret && type === MODAL_TYPES.EDIT"
        class="flex flex-col gap-1"
      >
        <label class="mb-0.5 text-sm font-medium text-n-slate-12">
          {{ $t('AGENT_BOTS.SECRET.LABEL') }}
        </label>
        <AccessToken
          :value="botSecret"
          @on-copy="onCopySecret"
          @on-reset="onResetSecret"
        />
      </div>

      <div v-if="showAccessTokenInput" class="flex flex-col gap-1">
        <label
          v-if="type === MODAL_TYPES.EDIT"
          class="mb-0.5 text-sm font-medium text-n-slate-12"
        >
          {{ $t('AGENT_BOTS.ACCESS_TOKEN.TITLE') }}
        </label>
        <AccessToken
          v-if="type === MODAL_TYPES.EDIT"
          :value="accessToken"
          @on-copy="onCopyToken"
          @on-reset="onResetToken"
        />
        <AccessToken
          v-else
          :value="accessToken"
          :show-reset-button="false"
          @on-copy="onCopyToken"
        />
      </div>

      <div
        v-if="botSecret && showAccessToken && type === MODAL_TYPES.CREATE"
        class="flex flex-col gap-1"
      >
        <p class="text-sm text-n-slate-11">
          {{ $t('AGENT_BOTS.SECRET.CREATED_DESC') }}
        </p>
        <label class="mb-0.5 text-sm font-medium text-n-slate-12">
          {{ $t('AGENT_BOTS.SECRET.LABEL') }}
        </label>
        <AccessToken
          :value="botSecret"
          :show-reset-button="false"
          @on-copy="onCopySecret"
        />
      </div>

      <div class="flex items-center justify-end w-full gap-2 px-0 py-2">
        <NextButton
          faded
          slate
          type="reset"
          :label="$t('AGENT_BOTS.FORM.CANCEL')"
          @click="onClickClose()"
        />
        <NextButton
          v-if="!showAccessToken"
          type="submit"
          data-testid="label-submit"
          :label="confirmButtonLabel"
          :is-loading="isLoading"
          :disabled="v$.$invalid"
        />
      </div>
    </form>
  </Dialog>

  <FlowBuilderModal ref="flowBuilderRef" v-model="formState.botConfig" />
</template>
