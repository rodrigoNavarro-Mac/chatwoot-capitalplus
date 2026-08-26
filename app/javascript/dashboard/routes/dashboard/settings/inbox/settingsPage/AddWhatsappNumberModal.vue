<script>
import { mapGetters } from 'vuex';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { isPhoneE164OrEmpty, isNumber } from 'shared/helpers/Validators';
import NextButton from 'dashboard/components-next/button/Button.vue';
import router from '../../../../index';

export default {
  components: { NextButton },
  props: {
    show: {
      type: Boolean,
      default: false,
    },
    businessAccountId: {
      type: String,
      default: '',
    },
    apiKey: {
      type: String,
      default: '',
    },
  },
  emits: ['close'],
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      inboxName: '',
      phoneNumber: '',
      phoneNumberId: '',
      localBusinessAccountId: this.businessAccountId,
      localApiKey: this.apiKey,
    };
  },
  computed: {
    ...mapGetters({ uiFlags: 'inboxes/getUIFlags' }),
  },
  validations: {
    inboxName: { required },
    phoneNumber: { required, isPhoneE164OrEmpty },
    phoneNumberId: { required, isNumber },
  },
  methods: {
    async createNumber() {
      this.v$.$touch();
      if (this.v$.$invalid) return;

      try {
        const newInbox = await this.$store.dispatch('inboxes/createChannel', {
          name: this.inboxName.trim(),
          channel: {
            type: 'whatsapp',
            phone_number: this.phoneNumber,
            provider: 'whatsapp_cloud',
            provider_config: {
              api_key: this.localApiKey,
              phone_number_id: this.phoneNumberId,
              business_account_id: this.localBusinessAccountId,
            },
          },
        });

        this.$emit('close');
        router.push({
          name: 'settings_inboxes_add_agents',
          params: { page: 'new', inbox_id: newInbox.id },
        });
      } catch (error) {
        useAlert(
          error.message || this.$t('INBOX_MGMT.ADD.WHATSAPP.API.ERROR_MESSAGE')
        );
      }
    },
  },
};
</script>

<template>
  <woot-modal :show="show" :on-close="() => $emit('close')">
    <div class="flex flex-col h-auto overflow-auto">
      <woot-modal-header
        :header-title="
          $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_ADD_NUMBER_MODAL_TITLE')
        "
        :header-content="
          $t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_ADD_NUMBER_MODAL_DESC')
        "
      />
      <form
        class="flex flex-wrap mx-0 px-8 pb-8"
        @submit.prevent="createNumber"
      >
        <div class="w-full">
          <label :class="{ error: v$.inboxName.$error }">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.LABEL') }}
            <input
              v-model="inboxName"
              type="text"
              :placeholder="
                $t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.PLACEHOLDER')
              "
              @blur="v$.inboxName.$touch"
            />
            <span v-if="v$.inboxName.$error" class="message">
              {{ $t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.ERROR') }}
            </span>
          </label>
        </div>

        <div class="w-full">
          <label :class="{ error: v$.phoneNumber.$error }">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.LABEL') }}
            <input
              v-model="phoneNumber"
              type="text"
              :placeholder="
                $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.PLACEHOLDER')
              "
              @blur="v$.phoneNumber.$touch"
            />
            <span v-if="v$.phoneNumber.$error" class="message">
              {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.ERROR') }}
            </span>
          </label>
        </div>

        <div class="w-full">
          <label :class="{ error: v$.phoneNumberId.$error }">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER_ID.LABEL') }}
            <input
              v-model="phoneNumberId"
              type="text"
              :placeholder="
                $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER_ID.PLACEHOLDER')
              "
              @blur="v$.phoneNumberId.$touch"
            />
            <span v-if="v$.phoneNumberId.$error" class="message">
              {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER_ID.ERROR') }}
            </span>
          </label>
        </div>

        <div class="flex justify-end gap-2 w-full mt-4">
          <NextButton
            outline
            slate
            type="button"
            :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_ADD_NUMBER_CANCEL')"
            @click="$emit('close')"
          />
          <NextButton
            solid
            blue
            type="submit"
            :is-loading="uiFlags.isCreating"
            :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_ADD_NUMBER_SUBMIT')"
          />
        </div>
      </form>
    </div>
  </woot-modal>
</template>
