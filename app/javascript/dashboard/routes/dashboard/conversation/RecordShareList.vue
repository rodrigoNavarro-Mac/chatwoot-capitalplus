<script>
import { useAlert } from 'dashboard/composables';
import { mapGetters } from 'vuex';
import { useAgentsList } from 'dashboard/composables/useAgentsList';

import MultiselectDropdownItems from 'shared/components/ui/MultiselectDropdownItems.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    MultiselectDropdownItems,
    NextButton,
  },
  props: {
    shareableType: {
      type: String,
      required: true,
    },
    shareableId: {
      type: [Number, String],
      required: true,
    },
  },
  setup() {
    const { agentsList } = useAgentsList(false);
    return { agentsList };
  },
  data() {
    return { showDropDown: false };
  },
  computed: {
    ...mapGetters({ teams: 'teams/getTeams' }),
    shares() {
      return this.$store.getters['recordShares/getShares'](
        this.shareableType,
        this.shareableId
      );
    },
    agentOptions() {
      return this.agentsList.map(agent => ({
        id: `user-${agent.id}`,
        name: agent.name,
        thumbnail: agent.thumbnail,
        availability_status: agent.availability_status,
        rawId: agent.id,
        shareType: 'User',
      }));
    },
    teamOptions() {
      return this.teams.map(team => ({
        id: `team-${team.id}`,
        name: team.name,
        icon: 'i-lucide-users',
        rawId: team.id,
        shareType: 'Team',
      }));
    },
    shareOptions() {
      return [...this.agentOptions, ...this.teamOptions];
    },
    sharedEntries() {
      return this.shares
        .map(share => {
          const option = this.shareOptions.find(
            candidate =>
              candidate.shareType === share.shared_with_type &&
              candidate.rawId === share.shared_with_id
          );
          if (!option) return null;
          return { ...option, shareId: share.id };
        })
        .filter(Boolean);
    },
  },
  watch: {
    shareableId() {
      this.fetchShares();
    },
  },
  mounted() {
    this.fetchShares();
    this.$store.dispatch('agents/get');
    this.$store.dispatch('teams/get');
  },
  methods: {
    fetchShares() {
      this.$store.dispatch('recordShares/fetch', {
        shareableType: this.shareableType,
        shareableId: this.shareableId,
      });
    },
    onOpenDropdown() {
      this.showDropDown = true;
    },
    onCloseDropdown() {
      this.showDropDown = false;
    },
    async onClickItem(option) {
      const existingEntry = this.sharedEntries.find(
        entry => entry.id === option.id
      );

      try {
        if (existingEntry) {
          await this.removeShare(existingEntry.shareId);
        } else {
          await this.$store.dispatch('recordShares/create', {
            shareableType: this.shareableType,
            shareableId: this.shareableId,
            sharedWithType: option.shareType,
            sharedWithId: option.rawId,
            accessLevel: 'view',
          });
        }
      } catch (error) {
        useAlert(error?.message || this.$t('RECORD_SHARE.API.ERROR_MESSAGE'));
      }
    },
    async removeShare(shareId) {
      await this.$store.dispatch('recordShares/remove', {
        id: shareId,
        shareableType: this.shareableType,
        shareableId: this.shareableId,
      });
    },
  },
};
</script>

<template>
  <div class="relative">
    <div class="flex items-center justify-between w-full mb-1">
      <p v-if="sharedEntries.length" class="m-0 text-sm total-watchers">
        {{
          $t('RECORD_SHARE.TOTAL_SHARED_TEXT', {
            count: sharedEntries.length,
          })
        }}
      </p>
      <p v-else class="m-0 text-sm text-n-slate-10">
        {{ $t('RECORD_SHARE.NO_SHARES_TEXT') }}
      </p>
      <NextButton
        v-tooltip.left="$t('RECORD_SHARE.SHARE_BUTTON')"
        slate
        ghost
        sm
        icon="i-lucide-share-2"
        class="relative -top-1"
        :title="$t('RECORD_SHARE.SHARE_BUTTON')"
        @click="onOpenDropdown"
      />
    </div>
    <div v-if="sharedEntries.length" class="flex flex-wrap gap-1.5">
      <span
        v-for="entry in sharedEntries"
        :key="entry.id"
        class="inline-flex items-center gap-1 text-xs bg-n-alpha-2 border border-n-weak rounded-full px-2 py-0.5"
      >
        <span :class="entry.icon || 'i-lucide-user'" class="text-n-slate-10" />
        {{ entry.name }}
        <button
          type="button"
          class="i-lucide-x text-n-slate-10 hover:text-n-ruby-9"
          :title="$t('RECORD_SHARE.REMOVE_BUTTON')"
          @click="removeShare(entry.shareId)"
        />
      </span>
    </div>
    <div
      v-on-clickaway="() => onCloseDropdown()"
      :class="{
        'block visible': showDropDown,
        'hidden invisible': !showDropDown,
      }"
      class="border rounded-lg shadow-lg bg-n-alpha-3 absolute backdrop-blur-[100px] border-n-strong dark:border-n-strong p-2 z-[9999] box-border top-8 w-full"
    >
      <div class="flex items-center justify-between mb-1">
        <h4
          class="m-0 overflow-hidden text-sm whitespace-nowrap text-ellipsis text-n-slate-12"
        >
          {{ $t('RECORD_SHARE.SHARE_BUTTON') }}
        </h4>
        <NextButton ghost slate xs icon="i-lucide-x" @click="onCloseDropdown" />
      </div>
      <MultiselectDropdownItems
        :options="shareOptions"
        :selected-items="sharedEntries"
        has-thumbnail
        @select="onClickItem"
      />
    </div>
  </div>
</template>
