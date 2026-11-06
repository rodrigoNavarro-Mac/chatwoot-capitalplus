<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';
import CampaignsAPI from 'dashboard/api/campaigns';
import ContactsAPI from 'dashboard/api/contacts';

import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// Per-campaign manual tweaks to a segment audience: remove specific segment members and add
// contacts that don't match it. Stored in campaign.audience as 'ExcludedContact' / 'Contact'
// items and resolved by Campaigns::SegmentAudience.
const props = defineProps({
  segmentId: { type: [Number, String], default: null },
});

const excluded = defineModel('excluded', { type: Array, default: () => [] });
const included = defineModel('included', { type: Array, default: () => [] });

const { t } = useI18n();

const isOpen = ref(false);
const activeTab = ref('remove');

const members = ref([]);
const membersQuery = ref('');
const membersPage = ref(1);
const membersCount = ref(0);
const isLoadingMembers = ref(false);
let membersToken = 0;

const searchQuery = ref('');
const searchResults = ref([]);
const isSearching = ref(false);
let searchToken = 0;

const excludedIds = computed(() => new Set(excluded.value.map(c => c.id)));
const includedIds = computed(() => new Set(included.value.map(c => c.id)));
const hasMoreMembers = computed(
  () => members.value.length < membersCount.value
);

const contactLabel = contact =>
  [contact.name, contact.phone_number].filter(Boolean).join(' · ');

const loadMembers = async ({ append = false } = {}) => {
  if (!props.segmentId) return;
  membersToken += 1;
  const token = membersToken;
  isLoadingMembers.value = true;
  try {
    const { data } = await CampaignsAPI.segmentContacts(props.segmentId, {
      query: membersQuery.value,
      page: membersPage.value,
    });
    if (token !== membersToken) return;
    members.value = append ? [...members.value, ...data.payload] : data.payload;
    membersCount.value = data.meta.count;
  } catch {
    if (token === membersToken) members.value = append ? members.value : [];
  } finally {
    if (token === membersToken) isLoadingMembers.value = false;
  }
};

const reloadMembers = () => {
  membersPage.value = 1;
  loadMembers();
};

const debouncedReloadMembers = debounce(reloadMembers, 300);

const loadMoreMembers = () => {
  membersPage.value += 1;
  loadMembers({ append: true });
};

const searchContacts = async () => {
  searchToken += 1;
  const token = searchToken;
  const query = searchQuery.value.trim();
  if (!query) {
    searchResults.value = [];
    return;
  }
  isSearching.value = true;
  try {
    const { data } = await ContactsAPI.search(query);
    if (token !== searchToken) return;
    searchResults.value = data.payload.map(({ id, name, phone_number }) => ({
      id,
      name,
      phone_number,
    }));
  } catch {
    if (token === searchToken) searchResults.value = [];
  } finally {
    if (token === searchToken) isSearching.value = false;
  }
};

const debouncedSearchContacts = debounce(searchContacts, 300);

const toggleExcluded = contact => {
  excluded.value = excludedIds.value.has(contact.id)
    ? excluded.value.filter(c => c.id !== contact.id)
    : [...excluded.value, contact];
};

const addContact = contact => {
  if (includedIds.value.has(contact.id)) return;
  included.value = [...included.value, contact];
};

const removeAdded = contact => {
  included.value = included.value.filter(c => c.id !== contact.id);
};

watch(membersQuery, debouncedReloadMembers);
watch(searchQuery, debouncedSearchContacts);

watch(
  () => [props.segmentId, isOpen.value],
  ([segmentId, open]) => {
    if (segmentId && open) reloadMembers();
  }
);
</script>

<template>
  <div class="flex flex-col gap-2 mt-2">
    <button
      type="button"
      class="flex items-center gap-1 text-sm font-medium text-n-blue-11 w-fit"
      @click="isOpen = !isOpen"
    >
      <span
        class="i-lucide-chevron-right size-4 transition-transform"
        :class="{ 'rotate-90': isOpen }"
      />
      {{
        t('CAMPAIGN.WHATSAPP.CREATE.FORM.SEGMENT_OVERRIDES.TOGGLE', {
          removed: excluded.length,
          added: included.length,
        })
      }}
    </button>

    <div
      v-if="isOpen"
      class="flex flex-col gap-3 p-3 border rounded-lg border-n-weak"
    >
      <div class="flex overflow-hidden border rounded-lg border-n-weak">
        <button
          type="button"
          class="flex-1 py-1.5 text-sm font-medium transition-colors"
          :class="
            activeTab === 'remove'
              ? 'bg-n-blue-9 text-white'
              : 'text-n-slate-11 hover:bg-n-alpha-2'
          "
          @click="activeTab = 'remove'"
        >
          {{
            t('CAMPAIGN.WHATSAPP.CREATE.FORM.SEGMENT_OVERRIDES.REMOVE_TAB', {
              count: excluded.length,
            })
          }}
        </button>
        <button
          type="button"
          class="flex-1 py-1.5 text-sm font-medium transition-colors"
          :class="
            activeTab === 'add'
              ? 'bg-n-blue-9 text-white'
              : 'text-n-slate-11 hover:bg-n-alpha-2'
          "
          @click="activeTab = 'add'"
        >
          {{
            t('CAMPAIGN.WHATSAPP.CREATE.FORM.SEGMENT_OVERRIDES.ADD_TAB', {
              count: included.length,
            })
          }}
        </button>
      </div>

      <!-- Remove segment members -->
      <template v-if="activeTab === 'remove'">
        <Input
          v-model="membersQuery"
          :placeholder="
            t('CAMPAIGN.WHATSAPP.CREATE.FORM.SEGMENT_OVERRIDES.SEARCH_MEMBERS')
          "
        />
        <div class="flex flex-col max-h-64 overflow-y-auto">
          <div
            v-for="contact in members"
            :key="contact.id"
            class="flex items-center justify-between gap-2 py-1.5 border-b last:border-b-0 border-n-weak"
          >
            <span
              class="text-sm truncate"
              :class="
                excludedIds.has(contact.id)
                  ? 'text-n-slate-10 line-through'
                  : 'text-n-slate-12'
              "
            >
              {{ contactLabel(contact) }}
            </span>
            <Button
              type="button"
              size="xs"
              variant="ghost"
              :color="excludedIds.has(contact.id) ? 'slate' : 'ruby'"
              :label="
                excludedIds.has(contact.id)
                  ? t('CAMPAIGN.WHATSAPP.CREATE.FORM.SEGMENT_OVERRIDES.RESTORE')
                  : t('CAMPAIGN.WHATSAPP.CREATE.FORM.SEGMENT_OVERRIDES.REMOVE')
              "
              @click="toggleExcluded(contact)"
            />
          </div>
          <div
            v-if="isLoadingMembers"
            class="flex items-center gap-2 py-2 text-xs text-n-slate-11"
          >
            <Spinner :size="14" />
          </div>
          <p v-else-if="!members.length" class="py-2 text-xs text-n-slate-11">
            {{
              t('CAMPAIGN.WHATSAPP.CREATE.FORM.SEGMENT_OVERRIDES.NO_MEMBERS')
            }}
          </p>
          <Button
            v-else-if="hasMoreMembers"
            type="button"
            size="xs"
            variant="link"
            class="mt-1 w-fit"
            :label="
              t('CAMPAIGN.WHATSAPP.CREATE.FORM.SEGMENT_OVERRIDES.LOAD_MORE')
            "
            @click="loadMoreMembers"
          />
        </div>
      </template>

      <!-- Add contacts outside the segment -->
      <template v-else>
        <Input
          v-model="searchQuery"
          :placeholder="
            t('CAMPAIGN.WHATSAPP.CREATE.FORM.SEGMENT_OVERRIDES.SEARCH_CONTACTS')
          "
        />
        <div class="flex flex-col max-h-48 overflow-y-auto">
          <div
            v-for="contact in searchResults"
            :key="contact.id"
            class="flex items-center justify-between gap-2 py-1.5 border-b last:border-b-0 border-n-weak"
          >
            <span class="text-sm truncate text-n-slate-12">
              {{ contactLabel(contact) }}
            </span>
            <Button
              type="button"
              size="xs"
              variant="ghost"
              :disabled="includedIds.has(contact.id)"
              :label="
                includedIds.has(contact.id)
                  ? t('CAMPAIGN.WHATSAPP.CREATE.FORM.SEGMENT_OVERRIDES.ADDED')
                  : t('CAMPAIGN.WHATSAPP.CREATE.FORM.SEGMENT_OVERRIDES.ADD')
              "
              @click="addContact(contact)"
            />
          </div>
          <div
            v-if="isSearching"
            class="flex items-center gap-2 py-2 text-xs text-n-slate-11"
          >
            <Spinner :size="14" />
          </div>
        </div>
        <div v-if="included.length" class="flex flex-wrap gap-1.5">
          <span
            v-for="contact in included"
            :key="contact.id"
            class="inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded-md bg-n-alpha-2 text-n-slate-12"
          >
            {{ contactLabel(contact) }}
            <button
              type="button"
              class="i-lucide-x size-3 text-n-slate-11 hover:text-n-slate-12"
              :aria-label="
                t('CAMPAIGN.WHATSAPP.CREATE.FORM.SEGMENT_OVERRIDES.REMOVE')
              "
              @click="removeAdded(contact)"
            />
          </span>
        </div>
      </template>

      <p class="text-xs text-n-slate-11">
        {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.SEGMENT_OVERRIDES.HELP') }}
      </p>
    </div>
  </div>
</template>
